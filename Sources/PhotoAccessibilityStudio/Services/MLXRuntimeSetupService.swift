import Foundation

final class MLXRuntimeSetupService {
    typealias ProgressHandler = (RuntimeProgress) -> Void

    private let metadataSetupService: RuntimeSetupService
    private let runner = ProcessRunner()
    private let streamingRunner = StreamingProcessRunner()
    private var serverProcess: Process?
    private var serverModelIdentifier: String?

    private let uvArchive = URL(string:
        "https://github.com/astral-sh/uv/releases/download/0.11.10/uv-aarch64-apple-darwin.tar.gz")!
    private let uvBytes: Int64 = 20_728_170
    private let uvSHA = "e93d6af7dfff7071edd16342ba9eeccfc28d8a7deaa5707efeecf63a63a74453"
    private let mlxVLMVersion = "0.6.6"
    private let port = 11_435

    init(metadataSetupService: RuntimeSetupService = .init()) {
        self.metadataSetupService = metadataSetupService
    }

    func inspect(model: VisionModel) async -> String? {
        var missing: [String] = []
        if let metadata = metadataSetupService.metadataToolMissingReason() {
            missing.append(metadata)
        }
        if !environmentReady {
            missing.append("MLX-VLM 推理环境")
        }
        if !isModelInstalled(model) {
            missing.append("\(model.displayName) 的 MLX 模型")
        }
        guard missing.isEmpty else { return missing.joined(separator: "、") }
        do {
            try await ensureServer(model: model)
        } catch {
            return "MLX-VLM 本地服务（\(error.localizedDescription)）"
        }
        return nil
    }

    func install(model: VisionModel,
                 progress: @escaping ProgressHandler) async throws {
        #if !arch(arm64)
        throw RuntimeSetupError.unsupportedPlatform("MLX 需要 Apple 芯片 Mac")
        #else
        try FileManager.default.createDirectory(at: RuntimePaths.mlxRoot,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: RuntimePaths.mlxModels,
                                                withIntermediateDirectories: true)
        try await metadataSetupService.installMetadataToolIfNeeded(progress: progress)
        try await installUVIfNeeded(progress: progress)
        try await installEnvironmentIfNeeded(progress: progress)
        if !isModelInstalled(model) {
            try await downloadModel(model, progress: progress)
        }
        guard environmentReady else {
            throw RuntimeSetupError.verificationFailed("MLX-VLM 环境不可执行")
        }
        guard isModelInstalled(model) else {
            throw RuntimeSetupError.verificationFailed("MLX 模型文件不完整")
        }
        progress(RuntimeProgress(step: "正在首次加载 \(model.displayName) 到 MLX",
                                 downloaded: 0,
                                 total: 0,
                                 bytesPerSecond: 0,
                                 detailOverride: "首次加载可能需要几十秒"))
        try await ensureServer(model: model)
        progress(RuntimeProgress(step: "MLX 与 \(model.displayName) 已配置完成",
                                 downloaded: 1,
                                 total: 1,
                                 bytesPerSecond: 0,
                                 detailOverride: "安装、模型和本地服务校验通过"))
        #endif
    }

    func installedModelNames() -> Set<String> {
        Set(VisionModel.allCases.compactMap { model in
            isModelInstalled(model) ? model.mlxName : nil
        })
    }

    func isModelInstalled(_ model: VisionModel) -> Bool {
        guard modelFilesPresent(model) else { return false }
        let marker = RuntimePaths.mlxModelRevisionMarker(for: model.mlxName)
        guard let revision = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return revision == model.mlxRevision
    }

    static func mostRecentIncompleteModel() -> VisionModel? {
        VisionModel.allCases
            .compactMap { model -> (VisionModel, Date)? in
                let directory = RuntimePaths.mlxModelDirectory(for: model.mlxName)
                guard FileManager.default.fileExists(atPath: directory.path),
                      directoryContainsDownloadedData(directory),
                      !revisionMarkerMatches(model) else { return nil }
                let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey])
                return (model, values?.contentModificationDate ?? .distantPast)
            }
            .max(by: { $0.1 < $1.1 })?.0
    }

    private static func directoryContainsDownloadedData(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        while let file = enumerator.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, (values?.fileSize ?? 0) > 0 { return true }
        }
        return false
    }

    private static func revisionMarkerMatches(_ model: VisionModel) -> Bool {
        let marker = RuntimePaths.mlxModelRevisionMarker(for: model.mlxName)
        let revision = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return revision == model.mlxRevision
    }

    private func modelFilesPresent(_ model: VisionModel) -> Bool {
        let directory = RuntimePaths.mlxModelDirectory(for: model.mlxName)
        let config = directory.appendingPathComponent("config.json")
        guard FileManager.default.isReadableFile(atPath: config.path),
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else { return false }
        while let file = enumerator.nextObject() as? URL {
            guard file.pathExtension == "safetensors" else { continue }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, (values?.fileSize ?? 0) > 1_000_000 {
                return true
            }
        }
        return false
    }

    private var environmentReady: Bool {
        guard FileManager.default.isExecutableFile(atPath: RuntimePaths.mlxPython.path),
              FileManager.default.isExecutableFile(atPath: RuntimePaths.mlxServer.path),
              let version = try? String(contentsOf: RuntimePaths.mlxVersionMarker,
                                        encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return version == mlxVLMVersion
    }

    private func installUVIfNeeded(progress: @escaping ProgressHandler) async throws {
        guard RuntimeToolLocator.uv() == nil else { return }
        let archive = try await RuntimeFileDownloader().download(
            from: uvArchive,
            step: "正在下载 MLX 环境安装器 uv",
            expectedBytes: uvBytes,
            expectedSHA256: uvSHA,
            progress: progress
        )
        defer { try? FileManager.default.removeItem(at: archive) }
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-uv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let result = try runner.run(executable: URL(fileURLWithPath: "/usr/bin/tar"),
                                    arguments: ["-xzf", archive.path, "-C", staging.path])
        guard result.status == 0,
              let source = executable(named: "uv", under: staging) else {
            throw RuntimeSetupError.archiveInvalid("uv 可执行文件缺失")
        }
        try FileManager.default.createDirectory(at: RuntimePaths.bin,
                                                withIntermediateDirectories: true)
        let temporary = RuntimePaths.bin.appendingPathComponent("uv.installing")
        try? FileManager.default.removeItem(at: temporary)
        try FileManager.default.copyItem(at: source, to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: temporary.path)
        try? FileManager.default.removeItem(at: RuntimePaths.uv)
        try FileManager.default.moveItem(at: temporary, to: RuntimePaths.uv)
    }

    private func installEnvironmentIfNeeded(progress: @escaping ProgressHandler) async throws {
        guard !environmentReady else { return }
        guard let uv = RuntimeToolLocator.uv() else {
            throw RuntimeSetupError.verificationFailed("uv 不可用")
        }
        let environment = processEnvironment
        progress(RuntimeProgress(step: "正在配置 MLX 专用 Python 3.12",
                                 downloaded: 0,
                                 total: 0,
                                 bytesPerSecond: 0,
                                 detailOverride: "缺少 Python 时会自动下载并校验"))
        if !FileManager.default.isExecutableFile(atPath: RuntimePaths.mlxPython.path) {
            let venv = try await runInBackground(
                executable: uv,
                arguments: ["venv", "--python", "3.12", "--managed-python",
                            RuntimePaths.mlxEnvironment.path],
                environment: environment,
                progress: progress,
                step: "正在配置 MLX 专用 Python 3.12"
            )
            guard venv.status == 0 else {
                throw RuntimeSetupError.modelPullFailed(venv.standardOutput)
            }
        }

        progress(RuntimeProgress(step: "正在安装 MLX-VLM 推理组件",
                                 downloaded: 0,
                                 total: 0,
                                 bytesPerSecond: 0,
                                 detailOverride: "固定版本 \(mlxVLMVersion)，不会修改系统 Python"))
        let install = try await runInBackground(
            executable: uv,
            arguments: ["pip", "install", "--python", RuntimePaths.mlxPython.path,
                        "mlx-vlm==\(mlxVLMVersion)"],
            environment: environment,
            progress: progress,
            step: "正在安装 MLX-VLM 推理组件"
        )
        guard install.status == 0 else {
            throw RuntimeSetupError.modelPullFailed(install.standardOutput)
        }
        try Data(mlxVLMVersion.utf8).write(to: RuntimePaths.mlxVersionMarker,
                                           options: .atomic)
        guard environmentReady else {
            throw RuntimeSetupError.verificationFailed("MLX-VLM 版本标记无效")
        }
    }

    private func downloadModel(_ model: VisionModel,
                               progress: @escaping ProgressHandler) async throws {
        let directory = RuntimePaths.mlxModelDirectory(for: model.mlxName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        progress(RuntimeProgress(step: "正在准备下载 \(model.displayName) 的 MLX 模型",
                                 downloaded: 0,
                                 total: 0,
                                 bytesPerSecond: 0,
                                 detailOverride: model.downloadSize(for: .mlx)))
        let marker = RuntimePaths.mlxModelRevisionMarker(for: model.mlxName)
        let installedRevision = try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let force = installedRevision != nil && installedRevision != model.mlxRevision
        let output = try await runInBackground(
            executable: RuntimePaths.mlxPython,
            arguments: ["-c", Self.modelDownloaderScript, model.mlxName,
                        model.mlxRevision, directory.path, force ? "1" : "0"],
            environment: processEnvironment,
            progress: progress,
            step: "正在下载 \(model.displayName) 的 MLX 模型",
            parsesJSONProgress: true
        )
        guard output.status == 0 else {
            throw RuntimeSetupError.modelPullFailed(Self.downloadFailure(from: output.standardOutput))
        }
        try Data(model.mlxRevision.utf8).write(to: marker, options: .atomic)
    }

    private static func downloadFailure(from output: String) -> String {
        for line in output.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONDecoder().decode(DownloadEvent.self, from: data),
                  let error = event.error, !error.isEmpty else { continue }
            return error
        }
        let lines = output.split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return lines.suffix(3).joined(separator: "；").prefix(600).description
    }

    private func runInBackground(executable: URL,
                                 arguments: [String],
                                 environment: [String: String],
                                 progress: @escaping ProgressHandler,
                                 step: String,
                                 parsesJSONProgress: Bool = false) async throws -> ProcessOutput {
        let runner = streamingRunner
        let task = Task.detached(priority: .utility) {
            try runner.run(executable: executable,
                           arguments: arguments,
                           environment: environment) { line in
                if parsesJSONProgress,
                   let data = line.data(using: .utf8),
                   let event = try? JSONDecoder().decode(DownloadEvent.self, from: data) {
                    progress(RuntimeProgress(step: event.error == nil ? event.step : "下载失败",
                                             downloaded: event.downloaded,
                                             total: event.total,
                                             bytesPerSecond: event.speed,
                                             detailOverride: event.error ?? event.detail))
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    progress(RuntimeProgress(step: step,
                                             downloaded: 0,
                                             total: 0,
                                             bytesPerSecond: 0,
                                             detailOverride: String(line.prefix(160))))
                }
            }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private struct DownloadEvent: Decodable {
        let step: String
        let downloaded: Int64
        let total: Int64
        let speed: Double
        let detail: String?
        let error: String?
    }

    private var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UV_CACHE_DIR"] = RuntimePaths.mlxCache.appendingPathComponent("uv").path
        environment["UV_PYTHON_INSTALL_DIR"] = RuntimePaths.mlxPythonInstallations.path
        environment["UV_NO_CONFIG"] = "1"
        environment["UV_LINK_MODE"] = "copy"
        environment["HF_HOME"] = RuntimePaths.mlxCache.appendingPathComponent("huggingface").path
        environment["HF_HUB_CACHE"] = RuntimePaths.mlxCache.appendingPathComponent("huggingface/hub").path
        environment["HF_XET_CACHE"] = RuntimePaths.mlxCache.appendingPathComponent("huggingface/xet").path
        environment["HF_HUB_DISABLE_XET"] = "1"
        environment["HF_HUB_ETAG_TIMEOUT"] = "30"
        environment["HF_HUB_DOWNLOAD_TIMEOUT"] = "60"
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private func ensureServer(model: VisionModel) async throws {
        if serverModelIdentifier == model.mlxName, await serverResponding() { return }
        stopServer()
        let process = Process()
        process.executableURL = RuntimePaths.mlxPython
        process.arguments = ["-m", "mlx_vlm.server",
                             "--model", RuntimePaths.mlxModelDirectory(for: model.mlxName).path,
                             "--host", "127.0.0.1",
                             "--port", String(port),
                             "--log-level", "ERROR"]
        process.environment = processEnvironment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        serverProcess = process
        serverModelIdentifier = model.mlxName
        for _ in 0..<1_200 {
            if await serverResponding() { return }
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        stopServer()
        throw RuntimeSetupError.serverUnavailable
    }

    private func serverResponding() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return false }
        return true
    }

    private func stopServer() {
        if serverProcess?.isRunning == true { serverProcess?.terminate() }
        serverProcess = nil
        serverModelIdentifier = nil
    }

    private func executable(named name: String, under directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == name,
               (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return item
            }
        }
        return nil
    }

    deinit { stopServer() }

    private static let modelDownloaderScript = #"""
import json
import os
import sys
import threading
import time
from pathlib import Path
from huggingface_hub import HfApi, hf_hub_download
from tqdm.auto import tqdm

repo_id = sys.argv[1]
revision = sys.argv[2]
local_dir = Path(sys.argv[3])
force_download = sys.argv[4] == "1"
local_dir.mkdir(parents=True, exist_ok=True)

state_lock = threading.Lock()
stop_monitor = threading.Event()
state = {
    "active": False,
    "filename": "正在读取模型文件列表",
    "downloaded": 0,
    "total": 0,
    "speed": 0.0,
    "last_change": time.monotonic(),
}

def emit(step, downloaded=0, total=0, speed=0.0, detail=None, error=None):
    print(json.dumps({
        "step": step,
        "downloaded": int(downloaded),
        "total": int(total),
        "speed": float(max(speed, 0.0)),
        "detail": detail,
        "error": error,
    }, ensure_ascii=False), flush=True)

def friendly_error(error):
    text = str(error).strip() or error.__class__.__name__
    lower = text.lower()
    if "401" in lower or "403" in lower or "unauthorized" in lower or "forbidden" in lower:
        return "模型仓库拒绝访问；请检查网络、模型许可和 Hugging Face 登录权限。原有进度已保留，可重试。"
    if "timed out" in lower or "timeout" in lower:
        return "连接模型服务器超时；请检查网络或代理后重试。原有进度已保留。"
    if "no space" in lower or "disk" in lower and "full" in lower:
        return "磁盘空间不足；请释放空间后重试。原有进度已保留。"
    if "name resolution" in lower or "cannot connect" in lower or "network" in lower:
        return "无法连接模型服务器；请检查网络、DNS 或代理后重试。原有进度已保留。"
    return "下载模型文件失败：" + text[:360] + "。原有进度已保留，可重试。"

def monitor():
    while not stop_monitor.wait(5):
        with state_lock:
            snapshot = dict(state)
        if not snapshot["active"]:
            continue
        idle = int(time.monotonic() - snapshot["last_change"])
        if idle >= 180:
            emit("下载已停止响应",
                 snapshot["downloaded"], snapshot["total"], 0,
                 error="连续 3 分钟没有收到任何模型数据，下载已停止。请检查网络、代理或防火墙后点击重试；已下载文件会保留并用于断点续传。")
            os._exit(70)
        detail = "正在连接模型文件服务器"
        if idle >= 15:
            detail = "连续 %d 秒未收到新数据，仍在等待；超过 3 分钟会自动停止并报告失败" % idle
        emit("正在下载 MLX 模型：" + snapshot["filename"],
             snapshot["downloaded"], snapshot["total"], snapshot["speed"], detail=detail)

threading.Thread(target=monitor, daemon=True).start()

try:
    emit("正在读取模型文件列表", detail="正在连接 Hugging Face 并核对固定模型版本")
    info = HfApi().model_info(repo_id, revision=revision, files_metadata=True)
    files = [s for s in info.siblings if s.rfilename not in {".gitattributes"} and not s.rfilename.lower().endswith((".md", ".png", ".jpg", ".jpeg"))]
    sizes = {s.rfilename: int(s.size or 0) for s in files}
    total = sum(sizes.values())
    completed = 0
    for sibling in files:
        target = local_dir / sibling.rfilename
        expected = sizes[sibling.rfilename]
        if not force_download and target.is_file() and (expected == 0 or target.stat().st_size == expected):
            completed += expected

    completed_at_start = completed
    started = time.monotonic()
    emit("正在核对已有模型文件", completed, total, detail="已完成的文件会跳过，未完成文件将断点续传")

    for sibling in files:
        filename = sibling.rfilename
        expected = sizes[filename]
        target = local_dir / filename
        if not force_download and target.is_file() and (expected == 0 or target.stat().st_size == expected):
            continue
        base = completed

        class Reporter(tqdm):
            def __init__(self, *args, **kwargs):
                kwargs["disable"] = True
                super().__init__(*args, **kwargs)
            def update(self, n=1):
                value = super().update(n)
                current = min(total, base + int(self.n))
                elapsed = max(time.monotonic() - started, 0.001)
                speed = max(current - completed_at_start, 0) / elapsed
                with state_lock:
                    if current > state["downloaded"]:
                        state["last_change"] = time.monotonic()
                    state.update(filename=filename, downloaded=current, total=total, speed=speed)
                emit("正在下载 MLX 模型：" + filename, current, total, speed)
                return value

        with state_lock:
            state.update(active=True, filename=filename, downloaded=base, total=total,
                         speed=0.0, last_change=time.monotonic())
        last_error = None
        for attempt in range(1, 4):
            try:
                hf_hub_download(repo_id=repo_id, revision=revision, filename=filename,
                                local_dir=str(local_dir), tqdm_class=Reporter,
                                force_download=force_download)
                last_error = None
                break
            except Exception as error:
                last_error = error
                if attempt < 3:
                    emit("模型下载连接中断，准备重试", base, total, 0,
                         detail="第 %d 次失败：%s；%d 秒后自动重试，已有进度保留" % (attempt, str(error)[:180], attempt * 2))
                    time.sleep(attempt * 2)
        if last_error is not None:
            raise last_error
        with state_lock:
            state["active"] = False
        actual = target.stat().st_size if target.is_file() else expected
        completed = min(total, base + (expected or actual))
        emit("已完成模型文件：" + filename, completed, total)

    emit("模型下载完成", total, total, detail="所有文件已下载，正在写入版本标记并验证")
except Exception as error:
    with state_lock:
        snapshot = dict(state)
        state["active"] = False
    emit("下载失败", snapshot["downloaded"], snapshot["total"], 0,
         error=friendly_error(error))
    sys.exit(1)
finally:
    stop_monitor.set()
"""#
}
