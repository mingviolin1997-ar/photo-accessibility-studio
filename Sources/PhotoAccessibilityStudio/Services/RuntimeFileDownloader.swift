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
        self.step = step
        fallbackTotal = expectedBytes
        progressHandler = progress
        lastDate = Date()
        lastBytes = 0
        smoothedSpeed = 0
        let file = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: source).resume()
        }
        let digest = try Self.sha256(of: file)
        guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            try? FileManager.default.removeItem(at: file)
            throw RuntimeSetupError.checksumMismatch(source.lastPathComponent)
        }
        return file
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
        defer { copiedURL = nil; progressHandler = nil }
        guard let continuation else { return }
        self.continuation = nil
        if let error {
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
