import Foundation

enum InferenceEngine: String, CaseIterable, Identifiable {
    case mlx
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlx: return "MLX"
        case .ollama: return "Ollama"
        }
    }

    var statusDescription: String {
        switch self {
        case .mlx:
            return "针对 Apple 芯片优化，通常速度更快、能耗更低。应用会按需安装 MLX-VLM 和独立运行环境。"
        case .ollama:
            return "兼容性成熟，继续使用本机 Ollama 服务；适合已经安装 Ollama 模型的用户。"
        }
    }

    var serviceAddress: String {
        switch self {
        case .mlx: return "127.0.0.1:11435"
        case .ollama: return "127.0.0.1:11434"
        }
    }

    static func stored(defaults: UserDefaults = .standard) -> InferenceEngine? {
        defaults.string(forKey: "selectedInferenceEngine").flatMap(Self.init(rawValue:))
    }
}
