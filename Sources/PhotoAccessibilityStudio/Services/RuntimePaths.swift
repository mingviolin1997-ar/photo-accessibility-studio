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
    static var uv: URL { bin.appendingPathComponent("uv") }
    static var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    static var downloads: URL { root.appendingPathComponent("downloads", isDirectory: true) }
    static var mlxRoot: URL { root.appendingPathComponent("mlx", isDirectory: true) }
    static var mlxEnvironment: URL { mlxRoot.appendingPathComponent("environment", isDirectory: true) }
    static var mlxPython: URL { mlxEnvironment.appendingPathComponent("bin/python") }
    static var mlxServer: URL { mlxEnvironment.appendingPathComponent("bin/mlx_vlm.server") }
    static var mlxVersionMarker: URL { mlxEnvironment.appendingPathComponent(".mlx-vlm-version") }
    static var mlxModels: URL { models.appendingPathComponent("mlx", isDirectory: true) }
    static var mlxCache: URL { mlxRoot.appendingPathComponent("cache", isDirectory: true) }
    static var mlxPythonInstallations: URL {
        mlxRoot.appendingPathComponent("python", isDirectory: true)
    }
    static var exifToolDirectory: URL { root.appendingPathComponent("exiftool", isDirectory: true) }
    static var exifToolScript: URL { exifToolDirectory.appendingPathComponent("exiftool") }

    static func mlxModelDirectory(for identifier: String) -> URL {
        let safe = identifier
            .replacingOccurrences(of: "/", with: "--")
            .replacingOccurrences(of: ":", with: "-")
        return mlxModels.appendingPathComponent(safe, isDirectory: true)
    }

    static func mlxModelRevisionMarker(for identifier: String) -> URL {
        mlxModelDirectory(for: identifier).appendingPathComponent(".pas-revision")
    }

    static func mlxModelManifest(for identifier: String) -> URL {
        mlxModelDirectory(for: identifier).appendingPathComponent(".pas-files.json")
    }

}

enum RuntimeToolLocator {
    static func uv() -> URL? {
        executable(firstOf: [
            RuntimePaths.uv.path,
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv"
        ])
    }

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
