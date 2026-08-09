import Foundation

struct StreamingProcessRunner {
    func run(executable: URL,
             arguments: [String],
             environment: [String: String]? = nil,
             onLine: ((String) -> Void)? = nil) throws -> ProcessOutput {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.cannotLaunch(error.localizedDescription)
        }

        var pending = Data()
        var captured = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if captured.count < 512_000 { captured.append(chunk) }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let lineData = pending[..<newline]
                pending.removeSubrange(...newline)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    onLine?(line)
                }
            }
        }
        process.waitUntilExit()
        if !pending.isEmpty,
           let line = String(data: pending, encoding: .utf8), !line.isEmpty {
            onLine?(line)
        }
        return ProcessOutput(status: process.terminationStatus,
                             standardOutput: String(data: captured, encoding: .utf8) ?? "",
                             standardError: "")
    }
}
