import Foundation

enum VisionModel: String, CaseIterable, Identifiable {
    case qwen35_4B
    case gemma4E2B
    case gemma4E4B
    case gemma3nE2B
    case gemma3nE4B

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen35_4B: return "Qwen 3.5 4B"
        case .gemma4E2B: return "Gemma 4 E2B"
        case .gemma4E4B: return "Gemma 4 E4B"
        case .gemma3nE2B: return "Gemma 3n E2B"
        case .gemma3nE4B: return "Gemma 3n E4B"
        }
    }

    var ollamaName: String {
        switch self {
        case .qwen35_4B: return "qwen3.5:4b"
        case .gemma4E2B: return "gemma4:e2b"
        case .gemma4E4B: return "gemma4:e4b"
        case .gemma3nE2B: return "gemma3n:e2b"
        case .gemma3nE4B: return "gemma3n:e4b"
        }
    }

    var mlxName: String {
        switch self {
        case .qwen35_4B: return "mlx-community/Qwen3.5-4B-MLX-4bit"
        case .gemma4E2B: return "mlx-community/gemma-4-e2b-it-4bit"
        case .gemma4E4B: return "mlx-community/gemma-4-e4b-it-4bit"
        case .gemma3nE2B: return "mlx-community/gemma-3n-E2B-it-4bit"
        case .gemma3nE4B: return "mlx-community/gemma-3n-E4B-it-4bit"
        }
    }

    var mlxRevision: String {
        switch self {
        case .qwen35_4B: return "32f3e8ecf65426fc3306969496342d504bfa13f3"
        case .gemma4E2B: return "238767527555cb75a05732a84dff5d6ba0dd6809"
        case .gemma4E4B: return "475b9088d29754a3379866cf5aeb6b41acd313c2"
        case .gemma3nE2B: return "66e7276cfc589073b4f92ebed58c05301f990222"
        case .gemma3nE4B: return "505468a22e5703ff090e222aae9beedec49b383f"
        }
    }

    func identifier(for engine: InferenceEngine) -> String {
        switch engine {
        case .mlx: return mlxName
        case .ollama: return ollamaName
        }
    }

    var downloadSize: String {
        switch self {
        case .qwen35_4B: return "约 3.4 GB"
        case .gemma4E2B: return "约 7.2 GB"
        case .gemma4E4B: return "约 9.6 GB"
        case .gemma3nE2B: return "约 5.6 GB"
        case .gemma3nE4B: return "约 7.5 GB"
        }
    }

    func downloadSize(for engine: InferenceEngine) -> String {
        guard engine == .mlx else { return downloadSize }
        switch self {
        case .qwen35_4B: return "约 3.1 GB"
        case .gemma4E2B: return "约 3.2 GB"
        case .gemma4E4B: return "约 5.0 GB"
        case .gemma3nE2B: return "约 4.5 GB"
        case .gemma3nE4B: return "约 5.9 GB"
        }
    }

    /// The current official Ollama Gemma 3n packages are published as text-only.
    /// Keep them downloadable for mobile/LiteRT-LM planning without allowing a
    /// selection that would silently ignore photos in this macOS Ollama build.
    var supportsPhotoRecognitionInMacApp: Bool {
        switch self {
        case .gemma3nE2B, .gemma3nE4B: return false
        default: return true
        }
    }

    func supportsPhotoRecognition(on engine: InferenceEngine) -> Bool {
        engine == .mlx || supportsPhotoRecognitionInMacApp
    }

    var recommendation: String {
        switch self {
        case .qwen35_4B:
            return "当前默认模型。适合 Apple 芯片 Mac，建议 16 GB 内存、macOS 14 或更高；中文照片描述均衡，下载体积最小。"
        case .gemma4E2B:
            return "偏速度和能耗。Mac 建议 16 GB 内存、macOS 14 或更高。移动端的 LiteRT-LM 专用版本约占 1.1 GB 运行内存，建议 iPhone 15 Pro 或更新机型；Android 建议 Android 14、8 GB 内存及较新的旗舰芯片。"
        case .gemma4E4B:
            return "偏识别质量，速度和发热高于 E2B。Mac 建议 24 GB 内存；移动端 LiteRT-LM 专用版本约占 2.5 GB 运行内存，建议 iPhone 16 Pro 或更新机型；Android 建议 12 GB 内存和旗舰级芯片。"
        case .gemma3nE2B:
            return "为手机和平板设计，LiteRT-LM 运行时动态内存约 2 GB。建议 iPhone 15 Pro 或更新机型，或 Android 14、8 GB 内存设备。当前 Ollama 官方包仅标注文本输入，因此 macOS 版可下载检测，但不会把它误设为照片识别模型。"
        case .gemma3nE4B:
            return "Gemma 3n 中质量更高的一档，LiteRT-LM 动态内存约 3 GB。建议 iPhone 16 Pro 或更新机型，或 Android 14、12 GB 内存旗舰设备。当前 Ollama 官方包仅标注文本输入，macOS 版只提供下载检测。"
        }
    }

    func recommendation(for engine: InferenceEngine) -> String {
        guard engine == .mlx else { return recommendation }
        switch self {
        case .qwen35_4B:
            return "默认推荐。约 3.1 GB 的 4-bit MLX 视觉模型，中文描述均衡；建议 Apple 芯片 Mac、16 GB 内存和 macOS 14 或更高。"
        case .gemma4E2B:
            return "偏速度和能耗，支持照片输入；建议 16 GB 内存。适合希望降低风扇噪声和批量处理时间的 Mac。"
        case .gemma4E4B:
            return "偏识别质量，支持照片输入，运行内存和发热高于 E2B；建议 24 GB 或更多内存。"
        case .gemma3nE2B:
            return "移动优先的多模态模型，在 MLX 中可直接识别照片；建议 16 GB 内存。Android/iPhone 仍优先使用 LiteRT-LM 专用包。"
        case .gemma3nE4B:
            return "Gemma 3n 中质量更高的一档，在 MLX 中可直接识别照片；建议 24 GB 内存。移动端建议 12 GB 内存旗舰设备。"
        }
    }

    var platformCompatibility: String {
        switch self {
        case .qwen35_4B:
            return "平台：macOS 支持 MLX 与 Ollama；Android 支持 LiteRT-LM；Windows 当前没有本软件版本，可在其他工具中使用兼容的 Ollama 模型。"
        case .gemma4E2B:
            return "平台：macOS 支持 MLX 与 Ollama；Android 支持 LiteRT-LM，适合 8 GB 内存设备；Windows 当前没有本软件版本。"
        case .gemma4E4B:
            return "平台：macOS 支持 MLX 与 Ollama，建议 24 GB 内存；Android 支持 LiteRT-LM，建议 12 GB 内存旗舰设备；Windows 当前没有本软件版本。"
        case .gemma3nE2B:
            return "平台：macOS 的 MLX 支持照片，Ollama 包暂不用于照片；Android 支持 LiteRT-LM；Windows 当前没有本软件版本。"
        case .gemma3nE4B:
            return "平台：macOS 的 MLX 支持照片，建议 24 GB 内存；Android 支持 LiteRT-LM，建议 12 GB 内存；Windows 当前没有本软件版本。"
        }
    }

    static func matching(ollamaName: String) -> VisionModel? {
        allCases.first { $0.ollamaName == ollamaName }
    }

    static func matching(identifier: String) -> VisionModel? {
        allCases.first { $0.ollamaName == identifier || $0.mlxName == identifier || $0.rawValue == identifier }
    }

    static func stored(defaults: UserDefaults = .standard) -> VisionModel {
        if let raw = defaults.string(forKey: "selectedVisionModelID"),
           let model = matching(identifier: raw) { return model }
        if let legacy = defaults.string(forKey: "selectedVisionModel"),
           let model = matching(identifier: legacy) { return model }
        return .qwen35_4B
    }
}
