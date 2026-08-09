import Foundation

struct ToolInvocation {
    let executable: URL
    let prefixArguments: [String]
}

enum RuntimePaths {
    static var root: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask).first!
        return support.appendingPathComponent("PhotoAccessibilityStudio/Runtime", isDirectory: true)
    }

    static var bin: URL { root.appendingPathComponent("bin", isDirectory: true) }
    static var ollama: URL { bin.appendingPathComponent("ollama") }
    static var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    static var exifToolDirectory: URL { root.appendingPathComponent("exiftool", isDirectory: true) }
    static var exifToolScript: URL { exifToolDirectory.appendingPathComponent("exiftool") }
}

enum RuntimeToolLocator {
    static func ollama() -> URL? {
        executable(firstOf: [
            RuntimePaths.ollama.path,
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/Applications/Ollama.app/Contents/Resources/ollama"
        ])
    }

    static func exifTool() -> ToolInvocation? {
        if FileManager.default.isReadableFile(atPath: RuntimePaths.exifToolScript.path) {
            return ToolInvocation(executable: URL(fileURLWithPath: "/usr/bin/perl"),
                                  prefixArguments: [RuntimePaths.exifToolScript.path])
        }
        guard let installed = executable(firstOf: [
            "/opt/homebrew/bin/exiftool", "/usr/local/bin/exiftool", "/usr/bin/exiftool"
        ]) else { return nil }
        return ToolInvocation(executable: installed, prefixArguments: [])
    }

    private static func executable(firstOf paths: [String]) -> URL? {
        paths.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }
}
