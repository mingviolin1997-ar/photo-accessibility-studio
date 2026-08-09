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

    var downloadSize: String {
        switch self {
        case .qwen35_4B: return "约 3.4 GB"
        case .gemma4E2B: return "约 7.2 GB"
        case .gemma4E4B: return "约 9.6 GB"
        case .gemma3nE2B: return "约 5.6 GB"
        case .gemma3nE4B: return "约 7.5 GB"
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

    static func matching(ollamaName: String) -> VisionModel? {
        allCases.first { $0.ollamaName == ollamaName }
    }
}
