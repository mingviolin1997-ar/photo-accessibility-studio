import Foundation

struct ProcessOutput {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessRunnerError: LocalizedError {
    case cannotLaunch(String)

    var errorDescription: String? {
        switch self {
        case let .cannotLaunch(message): return "无法启动元数据工具：\(message)"
        }
    }
}

struct ProcessRunner {
    func run(executable: URL, arguments: [String]) throws -> ProcessOutput {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.cannotLaunch(error.localizedDescription)
        }
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                           encoding: .utf8) ?? ""
        return ProcessOutput(status: process.terminationStatus,
                             standardOutput: output,
                             standardError: error)
    }
}
