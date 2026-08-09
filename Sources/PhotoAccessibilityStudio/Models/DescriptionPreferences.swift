import Foundation

enum DescriptionStyle: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case photographer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "低：快速了解"
        case .medium: return "中：均衡描述"
        case .high: return "高：详细描述"
        case .photographer: return "摄影家模式"
        }
    }

    var promptRequirement: String {
        switch self {
        case .low:
            return "用45至80个汉字，只保留主体、关键动作、最重要的空间关系和必须读出的文字，让盲人能在数秒内掌握照片。"
        case .medium:
            return "用80至150个汉字，描述主体、动作、前中后景、重要物体、可见文字、主要色彩与光线。可以用一句“画面给人……”表达有充分视觉依据的整体观感。"
        case .high:
            return "用150至260个汉字，完整描述主体细节、人物或动物、空间层次、环境、重要文字、颜色、光线、材质与整体氛围。可以用一句“画面给人……”表达有充分视觉依据的整体观感。"
        case .photographer:
            return "用160至280个汉字，从专业摄影角度描述主体；只选择画面证据确实支持的景别、机位、视角、构图、视觉重心、引导线、景深、焦点、曝光观感、光质、色彩关系或画面节奏，不必凑齐术语。主观审美判断必须用“画面给人……”明确标为观感。若图像不是现实照片，只描述适用的版式、形状、线条、配色和视觉重心，并明确其他摄影术语不适用。"
        }
    }
}

struct DescriptionPreferences: Equatable {
    var style: DescriptionStyle
    var includeCaptureAdvice: Bool

    static func load(defaults: UserDefaults = .standard) -> Self {
        let raw = defaults.string(forKey: "descriptionStyle") ?? DescriptionStyle.medium.rawValue
        return Self(style: DescriptionStyle(rawValue: raw) ?? .medium,
                    includeCaptureAdvice: defaults.bool(forKey: "includeCaptureAdvice"))
    }
}
