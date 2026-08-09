import CryptoKit
import Foundation

final class RuntimeFileDownloader: NSObject, URLSessionDataDelegate {
    typealias ProgressHandler = (RuntimeProgress) -> Void

    private var continuation: CheckedContinuation<URL, Error>?
    private var progressHandler: ProgressHandler?
    private var step = "正在下载"
    private var outputURL: URL?
    private var outputHandle: FileHandle?
    private var expectedBytes: Int64 = 0
    private var requestOffset: Int64 = 0
    private var currentDownloaded: Int64 = 0
    private var lastDate = Date()
    private var lastBytes: Int64 = 0
    private var lastProgressDate = Date()
    private var smoothedSpeed = 0.0
    private var responseFailure: Error?
    private var activeTask: URLSessionDataTask?
    private var heartbeatTimer: DispatchSourceTimer?
    private var stalled = false
    private var cancelledByCaller = false
    private var redirectCount = 0
    private let stateLock = NSLock()
    private let downloadDirectory: URL
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    init(downloadDirectory: URL = RuntimePaths.downloads) {
        self.downloadDirectory = downloadDirectory
        super.init()
    }

    func download(from source: URL,
                  step: String,
                  expectedBytes: Int64,
                  expectedSHA256: String,
                  progress: @escaping ProgressHandler) async throws -> URL {
        defer { session.finishTasksAndInvalidate() }
        try FileManager.default.createDirectory(at: downloadDirectory,
                                                withIntermediateDirectories: true)
        let partial = downloadDirectory
            .appendingPathComponent("\(expectedSHA256.lowercased()).part")
        if Self.fileSize(partial) > expectedBytes {
            try FileManager.default.removeItem(at: partial)
        }
        if Self.fileSize(partial) == expectedBytes {
            progress(RuntimeProgress(step: "正在校验已有下载文件",
                                     downloaded: expectedBytes,
                                     total: expectedBytes,
                                     bytesPerSecond: 0,
                                     detailOverride: "发现上次已下载文件，正在核对长度和 SHA-256"))
            if try Self.sha256(of: partial).caseInsensitiveCompare(expectedSHA256) == .orderedSame {
                return partial
            }
            try FileManager.default.removeItem(at: partial)
        }

        let probe = try await probeWithRetries(source: source,
                                               step: step,
                                               expectedBytes: expectedBytes,
                                               downloaded: Self.fileSize(partial),
                                               progress: progress)
        if let remoteTotal = probe.totalBytes, remoteTotal != expectedBytes {
            throw RuntimeSetupError.downloadFailed(
                "服务器文件大小为 \(RuntimeProgress.bytes(remoteTotal))，固定版本应为 " +
                "\(RuntimeProgress.bytes(expectedBytes))；已停止下载，请更新软件中的运行环境清单"
            )
        }
        progress(RuntimeProgress(
            step: "下载服务器连接正常",
            downloaded: Self.fileSize(partial),
            total: expectedBytes,
            bytesPerSecond: 0,
            detailOverride: "HTTP \(probe.statusCode)，\(probe.finalHost)，" +
                (probe.supportsRanges ? "支持断点续传" : "服务器未声明断点支持") +
                (probe.totalBytes.map { "；远端大小 \(RuntimeProgress.bytes($0)) 已匹配" } ?? "")
        ))
        try ensureStorage(for: partial, expectedBytes: expectedBytes)

        var lastError: Error = RuntimeSetupError.downloadFailed("未知错误")
        for attempt in 1...3 {
            do {
                let file = try await runAttempt(from: source,
                                                to: partial,
                                                step: step,
                                                expectedBytes: expectedBytes,
                                                attempt: attempt,
                                                progress: progress)
                let size = Self.fileSize(file)
                guard size == expectedBytes else {
                    throw RuntimeSetupError.downloadFailed(
                        "文件长度为 \(RuntimeProgress.bytes(size))，预期为 " +
                        RuntimeProgress.bytes(expectedBytes)
                    )
                }
                progress(RuntimeProgress(step: "正在校验下载文件",
                                         downloaded: expectedBytes,
                                         total: expectedBytes,
                                         bytesPerSecond: 0,
                                         detailOverride: "正在核对 SHA-256，确保文件完整"))
                let digest = try Self.sha256(of: file)
                guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
                    try? FileManager.default.removeItem(at: file)
                    throw RuntimeSetupError.checksumMismatch(source.lastPathComponent)
                }
                progress(RuntimeProgress(step: "下载与校验完成",
                                         downloaded: expectedBytes,
                                         total: expectedBytes,
                                         bytesPerSecond: 0,
                                         detailOverride: "固定文件长度和 SHA-256 均已通过"))
                return file
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 3 {
                    let completed = Self.fileSize(partial).coerce(maximum: expectedBytes)
                    progress(RuntimeProgress(
                        step: "下载中断，准备自动重试",
                        downloaded: completed,
                        total: expectedBytes,
                        bytesPerSecond: 0,
                        detailOverride: "\(RuntimeDownloadDiagnostics.message(for: error))；" +
                            "\(attempt * 2) 秒后第 \(attempt + 1) 次断点续传"
                    ))
                    try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
                }
            }
        }
        throw RuntimeSetupError.downloadFailed(
            "\(RuntimeDownloadDiagnostics.message(for: lastError))；已尝试 3 次，" +
            "已下载的 \(RuntimeProgress.bytes(Self.fileSize(partial))) 会保留供下次续传"
        )
    }

    private func probeWithRetries(source: URL,
                                  step: String,
                                  expectedBytes: Int64,
                                  downloaded: Int64,
                                  progress: @escaping ProgressHandler) async throws -> RuntimeRemoteProbe {
        var lastError: Error = RuntimeSetupError.downloadFailed("未知探测错误")
        let subject = downloadSubject(from: step)
        for attempt in 1...3 {
            progress(RuntimeProgress(step: "正在检测 \(subject)下载服务器",
                                     downloaded: downloaded,
                                     total: expectedBytes,
                                     bytesPerSecond: 0,
                                     detailOverride: "只读取响应头，检查权限、重定向、大小和断点支持；第 \(attempt) 次"))
            do {
                return try await RuntimeRemoteProber().probe(source)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 3 {
                    progress(RuntimeProgress(step: "下载服务器检测失败，准备重试",
                                             downloaded: downloaded,
                                             total: expectedBytes,
                                             bytesPerSecond: 0,
                                             detailOverride: "\(RuntimeDownloadDiagnostics.message(for: error))；" +
                                                "\(attempt * 2) 秒后重试"))
                    try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
                }
            }
        }
        throw RuntimeSetupError.downloadFailed(
            "\(RuntimeDownloadDiagnostics.message(for: lastError))；服务器检测已尝试 3 次"
        )
    }

    private func runAttempt(from source: URL,
                            to output: URL,
                            step: String,
                            expectedBytes: Int64,
                            attempt: Int,
                            progress: @escaping ProgressHandler) async throws -> URL {
        try prepareAttempt(output: output,
                           step: step,
                           expectedBytes: expectedBytes,
                           progress: progress)
        let offset = Self.fileSize(output).coerce(maximum: expectedBytes)
        let subject = downloadSubject(from: step)
        var request = URLRequest(url: source)
        request.timeoutInterval = 120
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("PhotoAccessibilityStudio-macOS/0.8", forHTTPHeaderField: "User-Agent")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        progress(RuntimeProgress(step: offset > 0 ? "正在断点续传 \(subject)" : step,
                                 downloaded: offset,
                                 total: expectedBytes,
                                 bytesPerSecond: 0,
                                 detailOverride: "第 \(attempt) 次连接；已有 " +
                                    RuntimeProgress.bytes(offset)))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<URL, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let task = session.dataTask(with: request)
                stateLock.lock()
                activeTask = task
                stateLock.unlock()
                startHeartbeat()
                task.resume()
            }
        } onCancel: {
            self.cancelCurrentDownload()
        }
    }

    private func prepareAttempt(output: URL,
                                step: String,
                                expectedBytes: Int64,
                                progress: @escaping ProgressHandler) throws {
        if !FileManager.default.fileExists(atPath: output.path) {
            FileManager.default.createFile(atPath: output.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: output)
        try handle.seekToEnd()
        let offset = Self.fileSize(output).coerce(maximum: expectedBytes)
        self.step = step
        self.outputURL = output
        self.outputHandle = handle
        self.expectedBytes = expectedBytes
        self.requestOffset = offset
        self.progressHandler = progress
        responseFailure = nil
        redirectCount = 0
        lastDate = Date()
        lastBytes = offset
        smoothedSpeed = 0
        stateLock.lock()
        currentDownloaded = offset
        lastProgressDate = Date()
        stalled = false
        cancelledByCaller = false
        stateLock.unlock()
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in self?.reportHeartbeat() }
        heartbeatTimer = timer
        timer.resume()
    }

    private func reportHeartbeat() {
        stateLock.lock()
        let idle = Date().timeIntervalSince(lastProgressDate)
        let downloaded = currentDownloaded
        let total = expectedBytes
        let task = activeTask
        if idle >= 180 { stalled = true }
        let didStall = stalled
        let speed = smoothedSpeed
        stateLock.unlock()
        if didStall {
            progressHandler?(RuntimeProgress(
                step: "下载已停止响应",
                downloaded: downloaded,
                total: total,
                bytesPerSecond: 0,
                detailOverride: "连续 3 分钟没有收到数据；现有文件已保留，正在停止并准备重试"
            ))
            task?.cancel()
        } else {
            let detail = idle >= 15
                ? "连续 \(Int(idle)) 秒未收到新数据，仍在等待；超过 3 分钟会自动断点重试"
                : "正在连接或等待下一批数据"
            progressHandler?(RuntimeProgress(step: step,
                                             downloaded: downloaded,
                                             total: total,
                                             bytesPerSecond: speed,
                                             detailOverride: detail))
        }
    }

    private func cancelCurrentDownload() {
        stateLock.lock()
        cancelledByCaller = true
        let task = activeTask
        stateLock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https" else {
            responseFailure = RuntimeSetupError.downloadFailed(
                "下载服务器重定向到了非 HTTPS 地址，已为安全起见停止"
            )
            completionHandler(nil)
            return
        }
        redirectCount += 1
        var redirected = request
        redirected.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        redirected.setValue("PhotoAccessibilityStudio-macOS/0.8",
                            forHTTPHeaderField: "User-Agent")
        if requestOffset > 0 {
            redirected.setValue("bytes=\(requestOffset)-", forHTTPHeaderField: "Range")
        }
        completionHandler(redirected)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            responseFailure = RuntimeSetupError.downloadFailed("下载服务器返回了无法识别的响应")
            completionHandler(.cancel)
            return
        }
        guard http.url?.scheme?.lowercased() == "https" else {
            responseFailure = RuntimeSetupError.downloadFailed("下载被重定向到非 HTTPS 地址，已停止")
            completionHandler(.cancel)
            return
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            responseFailure = RuntimeSetupError.downloadFailed("下载服务器拒绝访问；请检查许可或账号权限")
            completionHandler(.cancel)
            return
        }
        if requestOffset > 0 && http.statusCode == 416 {
            do {
                try outputHandle?.truncate(atOffset: 0)
                try outputHandle?.seek(toOffset: 0)
                requestOffset = 0
                stateLock.lock()
                currentDownloaded = 0
                lastBytes = 0
                lastProgressDate = Date()
                stateLock.unlock()
                responseFailure = RuntimeSetupError.downloadFailed(
                    "服务器不接受现有断点；已安全清理该临时文件，将从零重新连接"
                )
            } catch {
                responseFailure = error
            }
            completionHandler(.cancel)
            return
        }
        if requestOffset > 0 && http.statusCode == 200 {
            do {
                try outputHandle?.truncate(atOffset: 0)
                try outputHandle?.seek(toOffset: 0)
                requestOffset = 0
                stateLock.lock()
                currentDownloaded = 0
                lastBytes = 0
                lastProgressDate = Date()
                stateLock.unlock()
            } catch {
                responseFailure = error
                completionHandler(.cancel)
                return
            }
        } else if http.statusCode == 206 {
            do {
                try validateContentRange(http, expectedStart: requestOffset, expectedTotal: expectedBytes)
            } catch {
                responseFailure = error
                completionHandler(.cancel)
                return
            }
        } else if http.statusCode != 200 {
            responseFailure = RuntimeSetupError.downloadFailed("下载服务器返回 HTTP \(http.statusCode)")
            completionHandler(.cancel)
            return
        }
        if http.statusCode == 200,
           http.expectedContentLength > 0,
           http.expectedContentLength != expectedBytes {
            responseFailure = RuntimeSetupError.downloadFailed(
                "服务器文件长度为 \(RuntimeProgress.bytes(http.expectedContentLength))，" +
                "预期为 \(RuntimeProgress.bytes(expectedBytes))"
            )
            completionHandler(.cancel)
            return
        }
        progressHandler?(RuntimeProgress(
            step: requestOffset > 0 ? "断点连接已建立" : "下载连接已建立",
            downloaded: requestOffset,
            total: expectedBytes,
            bytesPerSecond: 0,
            detailOverride: "HTTP \(http.statusCode)，经过 \(redirectCount) 次安全重定向到 " +
                (http.url?.host ?? "下载服务器")
        ))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        do {
            try outputHandle?.write(contentsOf: data)
            let now = Date()
            stateLock.lock()
            currentDownloaded += Int64(data.count)
            let downloaded = currentDownloaded
            lastProgressDate = now
            let elapsed = now.timeIntervalSince(lastDate)
            if elapsed >= 0.25 {
                let instant = Double(downloaded - lastBytes) / elapsed
                smoothedSpeed = smoothedSpeed == 0 ? instant : smoothedSpeed * 0.7 + instant * 0.3
                lastDate = now
                lastBytes = downloaded
            }
            let reportedSpeed = smoothedSpeed
            stateLock.unlock()
            if downloaded > expectedBytes {
                responseFailure = RuntimeSetupError.downloadFailed(
                    "服务器返回的数据超过固定文件长度，已停止以避免保存损坏文件"
                )
                dataTask.cancel()
                return
            }
            progressHandler?(RuntimeProgress(step: step,
                                             downloaded: downloaded,
                                             total: expectedBytes,
                                             bytesPerSecond: reportedSpeed))
        } catch {
            responseFailure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        try? outputHandle?.synchronize()
        try? outputHandle?.close()
        outputHandle = nil
        stateLock.lock()
        activeTask = nil
        let didStall = stalled
        let wasCancelled = cancelledByCaller
        stateLock.unlock()
        defer { progressHandler = nil }
        guard let continuation else { return }
        self.continuation = nil
        if wasCancelled {
            continuation.resume(throwing: CancellationError())
        } else if let responseFailure {
            continuation.resume(throwing: responseFailure)
        } else if didStall {
            continuation.resume(throwing: RuntimeSetupError.downloadFailed(
                "连续 3 分钟没有收到数据；请检查网络、代理或防火墙"
            ))
        } else if let error {
            continuation.resume(throwing: error)
        } else if let outputURL {
            continuation.resume(returning: outputURL)
        } else {
            continuation.resume(throwing: RuntimeSetupError.downloadFailed("下载结束但没有生成文件"))
        }
    }

    private func validateContentRange(_ response: HTTPURLResponse,
                                      expectedStart: Int64,
                                      expectedTotal: Int64) throws {
        guard let header = response.value(forHTTPHeaderField: "Content-Range") else {
            throw RuntimeSetupError.downloadFailed("服务器返回断点数据，但缺少 Content-Range")
        }
        let pattern = #"bytes\s+(\d+)-(\d+)/(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern,
                                                        options: [.caseInsensitive]),
              let match = expression.firstMatch(in: header,
                                                range: NSRange(header.startIndex..., in: header)),
              let startRange = Range(match.range(at: 1), in: header),
              let totalRange = Range(match.range(at: 3), in: header),
              let actualStart = Int64(header[startRange]),
              let actualTotal = Int64(header[totalRange]),
              actualStart == expectedStart,
              actualTotal == expectedTotal else {
            throw RuntimeSetupError.downloadFailed(
                "断点响应不匹配：\(header)；预期从 \(expectedStart) 字节开始、" +
                "总长 \(RuntimeProgress.bytes(expectedTotal))"
            )
        }
    }

    private func ensureStorage(for partial: URL, expectedBytes: Int64) throws {
        let completed = Self.fileSize(partial).coerce(maximum: expectedBytes)
        let missing = max(0, expectedBytes - completed)
        let values = try downloadDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else { return }
        let reserve: Int64 = 256 * 1024 * 1024
        guard available >= missing + reserve else {
            throw RuntimeSetupError.downloadFailed(
                "磁盘空间不足：还需下载 \(RuntimeProgress.bytes(missing))，并保留 256 MB 运行空间；" +
                "当前可用 \(RuntimeProgress.bytes(available))"
            )
        }
    }

    private func downloadSubject(from step: String) -> String {
        if step.hasPrefix("正在下载 ") { return String(step.dropFirst("正在下载 ".count)) }
        if step.hasPrefix("正在下载") { return String(step.dropFirst("正在下载".count)) }
        return step
    }

    private static func fileSize(_ url: URL?) -> Int64 {
        guard let path = url?.path,
              let value = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
        else { return 0 }
        return value.int64Value
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension Int64 {
    func coerce(maximum: Int64) -> Int64 { Swift.min(Swift.max(0, self), maximum) }
}
