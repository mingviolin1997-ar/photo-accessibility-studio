import Foundation

final class RuntimeSetupService {
    typealias ProgressHandler = (RuntimeProgress) -> Void

    private let runner = ProcessRunner()
    private var ollamaProcess: Process?

    private let ollamaArchive = URL(string:
        "https://github.com/ollama/ollama/releases/download/v0.32.6/ollama-darwin.tgz")!
    private let ollamaBytes: Int64 = 145_435_565
    private let ollamaSHA = "c256147703b0b24a9871ec9f94fc108f18cf87ff043aebd6f7e4a95fcfb4f042"
    private let exifArchive = URL(string:
        "https://sourceforge.net/projects/exiftool/files/Image-ExifTool-13.59.tar.gz/download")!
    private let exifBytes: Int64 = 7_916_358
    private let exifSHA = "668ea3acececb7235fbd0f4900e72d5f12c9b07e5c778fd36cb1e9b5828fd65a"

    init() {}

    func metadataToolMissingReason() -> String? {
        RuntimeToolLocator.exifTool() == nil ? "ExifTool 元数据环境" : nil
    }

    func installMetadataToolIfNeeded(progress: @escaping ProgressHandler) async throws {
        guard RuntimeToolLocator.exifTool() == nil else { return }
        try FileManager.default.createDirectory(at: RuntimePaths.root,
                                                withIntermediateDirectories: true)
        let archive = try await RuntimeFileDownloader().download(
            from: exifArchive,
            step: "正在下载 ExifTool 元数据环境",
            expectedBytes: exifBytes,
            expectedSHA256: exifSHA,
            progress: progress
        )
        defer { try? FileManager.default.removeItem(at: archive) }
        try installExifTool(from: archive)
    }

    func inspect(modelName: String = AppConfiguration().modelName) async -> String? {
        var missing: [String] = []
        if RuntimeToolLocator.exifTool() == nil { missing.append("ExifTool 元数据环境") }

        if !(await serverResponding()), let executable = RuntimeToolLocator.ollama() {
            try? startOllama(executable)
            _ = await waitForServer()
        }
        if !(await serverResponding()) {
            missing.append("Ollama 本地推理环境")
        } else {
            do { try await client(for: modelName).checkHealth() }
            catch { missing.append("\(modelDisplayName(modelName)) 模型") }
        }
        return missing.isEmpty ? nil : missing.joined(separator: "、")
    }

    func install(modelName: String = AppConfiguration().modelName,
                 progress: @escaping ProgressHandler) async throws {
        try FileManager.default.createDirectory(at: RuntimePaths.root,
                                                withIntermediateDirectories: true)
        try await installMetadataToolIfNeeded(progress: progress)

        if !(await serverResponding()) {
            var executable = RuntimeToolLocator.ollama()
            if executable == nil {
                let archive = try await RuntimeFileDownloader().download(
                    from: ollamaArchive,
                    step: "正在下载 Ollama 本地推理环境",
                    expectedBytes: ollamaBytes,
                    expectedSHA256: ollamaSHA,
                    progress: progress
                )
                defer { try? FileManager.default.removeItem(at: archive) }
                try installOllama(from: archive)
                executable = RuntimeToolLocator.ollama()
            }
            guard let executable else { throw RuntimeSetupError.archiveInvalid("未找到 Ollama") }
            try startOllama(executable)
            guard await waitForServer() else { throw RuntimeSetupError.serverUnavailable }
        }

        do { try await client(for: modelName).checkHealth() }
        catch { try await pullModel(modelName: modelName, progress: progress) }

        guard RuntimeToolLocator.exifTool() != nil else {
            throw RuntimeSetupError.verificationFailed("ExifTool 不可用")
        }
        do { try await client(for: modelName).checkHealth() }
        catch { throw RuntimeSetupError.verificationFailed(error.localizedDescription) }
        progress(RuntimeProgress(step: "本地环境与 \(modelDisplayName(modelName)) 已配置完成",
                                 downloaded: 1, total: 1, bytesPerSecond: 0))
    }

    func installedModelNames() async -> Set<String> {
        if !(await serverResponding()), let executable = RuntimeToolLocator.ollama() {
            try? startOllama(executable)
            _ = await waitForServer()
        }
        guard await serverResponding() else { return [] }
        return (try? await client(for: VisionModel.qwen35_4B.ollamaName).installedModelNames()) ?? []
    }

    private func installOllama(from archive: URL) throws {
        let staging = try extract(archive)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard let source = firstFile(named: "ollama", under: staging) else {
            throw RuntimeSetupError.archiveInvalid("Ollama 可执行文件缺失")
        }
        try FileManager.default.createDirectory(at: RuntimePaths.bin,
                                                withIntermediateDirectories: true)
        let temporary = RuntimePaths.bin.appendingPathComponent("ollama.installing")
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: temporary.path)
        try? FileManager.default.removeItem(at: RuntimePaths.ollama)
        try FileManager.default.moveItem(at: temporary, to: RuntimePaths.ollama)
    }

    private func installExifTool(from archive: URL) throws {
        let staging = try extract(archive)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard let script = firstFile(named: "exiftool", under: staging),
              FileManager.default.fileExists(atPath:
                script.deletingLastPathComponent().appendingPathComponent("lib").path) else {
            throw RuntimeSetupError.archiveInvalid("ExifTool 脚本或 lib 目录缺失")
        }
        let source = script.deletingLastPathComponent()
        let temporary = RuntimePaths.root.appendingPathComponent("exiftool.installing")
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.copyItem(at: source, to: temporary)
        try? FileManager.default.removeItem(at: RuntimePaths.exifToolDirectory)
        try FileManager.default.moveItem(at: temporary, to: RuntimePaths.exifToolDirectory)
    }

    private func extract(_ archive: URL) throws -> URL {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-extract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let output = try runner.run(executable: URL(fileURLWithPath: "/usr/bin/tar"),
                                    arguments: ["-xzf", archive.path, "-C", staging.path])
        guard output.status == 0 else {
            throw RuntimeSetupError.archiveInvalid(output.standardError)
        }
        return staging
    }

    private func firstFile(named name: String, under directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == name,
               (try? item.resourceValues(forKeys: Set(keys)).isRegularFile) == true { return item }
        }
        return nil
    }

    private func startOllama(_ executable: URL) throws {
        guard ollamaProcess?.isRunning != true else { return }
        try FileManager.default.createDirectory(at: RuntimePaths.models,
                                                withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["OLLAMA_HOST"] = "127.0.0.1:11434"
        if executable.path == RuntimePaths.ollama.path {
            environment["OLLAMA_MODELS"] = RuntimePaths.models.path
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        ollamaProcess = process
    }

    private func serverResponding() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 2
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              !data.isEmpty else { return false }
        return true
    }

    private func waitForServer() async -> Bool {
        for _ in 0..<80 {
            if await serverResponding() { return true }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }

    private func pullModel(modelName: String,
                           progress: @escaping ProgressHandler) async throws {
        struct PullRequest: Encodable { let model: String; let stream = true }
        struct PullStatus: Decodable {
            let status: String?
            let digest: String?
            let total: Int64?
            let completed: Int64?
            let error: String?
        }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/pull")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 12 * 60 * 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PullRequest(model: modelName))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 12 * 60 * 60
        let session = URLSession(configuration: configuration)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RuntimeSetupError.modelPullFailed("Ollama 服务拒绝下载")
        }
        var lastDigest = ""
        var lastBytes: Int64 = 0
        var lastTime = Date()
        var speed = 0.0
        for try await line in bytes.lines where !line.isEmpty {
            let value = try JSONDecoder().decode(PullStatus.self, from: Data(line.utf8))
            if let error = value.error { throw RuntimeSetupError.modelPullFailed(error) }
            let completed = value.completed ?? 0
            let total = value.total ?? 0
            if value.digest != lastDigest || completed < lastBytes {
                lastDigest = value.digest ?? ""
                lastBytes = completed
                lastTime = Date()
                speed = 0
            }
            let now = Date()
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= 0.25 {
                let instant = Double(completed - lastBytes) / elapsed
                speed = speed == 0 ? instant : speed * 0.7 + instant * 0.3
                lastBytes = completed
                lastTime = now
            }
            progress(RuntimeProgress(step: value.status ?? "正在下载 \(modelDisplayName(modelName)) 模型",
                                     downloaded: completed,
                                     total: total,
                                     bytesPerSecond: speed))
        }
    }

    private func client(for modelName: String) -> OllamaClient {
        OllamaClient(configuration: AppConfiguration(modelName: modelName))
    }

    private func modelDisplayName(_ modelName: String) -> String {
        VisionModel.matching(ollamaName: modelName)?.displayName ?? modelName
    }

    deinit {
        if ollamaProcess?.isRunning == true { ollamaProcess?.terminate() }
    }
}
