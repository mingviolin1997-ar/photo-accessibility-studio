import CryptoKit
import Foundation

final class RuntimeFileDownloader: NSObject, URLSessionDownloadDelegate {
    typealias ProgressHandler = (RuntimeProgress) -> Void

    private var continuation: CheckedContinuation<URL, Error>?
    private var copiedURL: URL?
    private var progressHandler: ProgressHandler?
    private var step = "正在下载"
    private var fallbackTotal: Int64 = 0
    private var lastDate = Date()
    private var lastBytes: Int64 = 0
    private var smoothedSpeed = 0.0
    private var activeTask: URLSessionDownloadTask?
    private var heartbeatTimer: DispatchSourceTimer?
    private var lastProgressDate = Date()
    private var currentDownloaded: Int64 = 0
    private var currentTotal: Int64 = 0
    private var stalled = false
    private var cancelledByCaller = false
    private let stateLock = NSLock()
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()

    func download(from source: URL,
                  step: String,
                  expectedBytes: Int64,
                  expectedSHA256: String,
                  progress: @escaping ProgressHandler) async throws -> URL {
        var lastError: Error = RuntimeSetupError.downloadFailed("未知错误")
        for attempt in 1...3 {
            prepareAttempt(step: step, expectedBytes: expectedBytes, progress: progress)
            progress(RuntimeProgress(step: step,
                                     downloaded: 0,
                                     total: expectedBytes,
                                     bytesPerSecond: 0,
                                     detailOverride: attempt == 1
                                        ? "正在连接下载服务器"
                                        : "第 \(attempt) 次尝试；前一次连接失败"))
            do {
                let file = try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation {
                        (continuation: CheckedContinuation<URL, Error>) in
                        if Task.isCancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        self.continuation = continuation
                        let task = session.downloadTask(with: source)
                        stateLock.lock()
                        activeTask = task
                        stateLock.unlock()
                        startHeartbeat()
                        task.resume()
                    }
                } onCancel: {
                    self.cancelCurrentDownload()
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
                return file
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 3 {
                    progress(RuntimeProgress(step: "下载中断，准备自动重试",
                                             downloaded: currentDownloaded,
                                             total: expectedBytes,
                                             bytesPerSecond: 0,
                                             detailOverride: "\(error.localizedDescription)；2 秒后重试"))
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError
    }

    private func prepareAttempt(step: String,
                                expectedBytes: Int64,
                                progress: @escaping ProgressHandler) {
        self.step = step
        fallbackTotal = expectedBytes
        progressHandler = progress
        lastDate = Date()
        lastBytes = 0
        smoothedSpeed = 0
        stateLock.lock()
        currentDownloaded = 0
        currentTotal = expectedBytes
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
        let total = currentTotal
        let task = activeTask
        if idle >= 180 { stalled = true }
        let didStall = stalled
        stateLock.unlock()
        if didStall {
            progressHandler?(RuntimeProgress(
                step: "下载已停止响应",
                downloaded: downloaded,
                total: total,
                bytesPerSecond: 0,
                detailOverride: "连续 3 分钟没有收到数据；正在停止并准备报告失败"
            ))
            task?.cancel()
        } else {
            let detail = idle >= 15
                ? "连续 \(Int(idle)) 秒未收到新数据，仍在等待；超过 3 分钟会自动停止"
                : "正在连接或等待下一批数据"
            progressHandler?(RuntimeProgress(step: step,
                                             downloaded: downloaded,
                                             total: total,
                                             bytesPerSecond: smoothedSpeed,
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
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastDate)
        if elapsed >= 0.25 {
            let instant = Double(totalBytesWritten - lastBytes) / elapsed
            smoothedSpeed = smoothedSpeed == 0 ? instant : smoothedSpeed * 0.7 + instant * 0.3
            lastDate = now
            lastBytes = totalBytesWritten
        }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : fallbackTotal
        stateLock.lock()
        currentDownloaded = totalBytesWritten
        currentTotal = total
        lastProgressDate = now
        stateLock.unlock()
        progressHandler?(RuntimeProgress(step: step,
                                         downloaded: totalBytesWritten,
                                         total: total,
                                         bytesPerSecond: smoothedSpeed))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { return }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("pas-runtime-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: location, to: destination)
            copiedURL = destination
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        stateLock.lock()
        activeTask = nil
        let didStall = stalled
        let wasCancelled = cancelledByCaller
        stateLock.unlock()
        defer { copiedURL = nil; progressHandler = nil }
        guard let continuation else { return }
        self.continuation = nil
        if wasCancelled {
            continuation.resume(throwing: CancellationError())
        } else if didStall {
            continuation.resume(throwing: RuntimeSetupError.downloadFailed(
                "连续 3 分钟没有收到数据；请检查网络、代理或防火墙后重试"
            ))
        } else if let error {
            continuation.resume(throwing: RuntimeSetupError.downloadFailed(error.localizedDescription))
        } else if let copiedURL {
            continuation.resume(returning: copiedURL)
        } else {
            let code = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            continuation.resume(throwing: RuntimeSetupError.downloadFailed("HTTP \(code)"))
        }
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
