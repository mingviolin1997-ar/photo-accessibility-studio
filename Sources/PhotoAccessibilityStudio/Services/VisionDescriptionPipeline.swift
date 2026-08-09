import Foundation

struct VisionSchemaItems: Encodable {
    let type: String
}

struct VisionSchemaProperty: Encodable {
    let type: String
    var items: VisionSchemaItems?

    init(_ type: String, items: VisionSchemaItems? = nil) {
        self.type = type
        self.items = items
    }
}

struct VisionJSONSchema: Encodable {
    let type = "object"
    let properties: [String: VisionSchemaProperty]
    let required: [String]
    let additionalProperties = false

    static let generated = VisionJSONSchema(
        properties: [
            "isPhoto": VisionSchemaProperty("boolean"),
            "description": VisionSchemaProperty("string"),
            "advice": VisionSchemaProperty("string"),
            "needsReview": VisionSchemaProperty("boolean"),
            "uncertainties": VisionSchemaProperty("array", items: VisionSchemaItems(type: "string"))
        ],
        required: ["isPhoto", "description", "advice", "needsReview", "uncertainties"]
    )

    static let review = VisionJSONSchema(
        properties: [
            "approved": VisionSchemaProperty("boolean"),
            "issues": VisionSchemaProperty("array", items: VisionSchemaItems(type: "string"))
        ],
        required: ["approved", "issues"]
    )
}

struct VisionDescriptionPipeline {
    typealias Request = (_ imageBase64: String,
                         _ prompt: String,
                         _ schema: VisionJSONSchema,
                         _ temperature: Double,
                         _ maximumTokens: Int) async throws -> String

    private struct GeneratedContent: Decodable {
        let isPhoto: Bool
        let description: String
        let advice: String
        let needsReview: Bool
        let uncertainties: [String]
    }

    private struct ReviewContent: Decodable {
        let approved: Bool
        let issues: [String]
    }

    let imageEncoder: ImageEncoder
    let maximumImageDimension: CGFloat

    func describe(_ imageURL: URL,
                  preferences: DescriptionPreferences,
                  onStage: ((String) -> Void)?,
                  request: @escaping Request) async throws -> String {
        onStage?("正在节能预处理照片")
        let encoder = imageEncoder
        let dimension = maximumImageDimension
        let encoded = try await Task.detached(priority: .utility) {
            try encoder.encode(for: imageURL, maximumDimension: dimension)
        }.value
        AppLogger.shared.log(
            "模型输入已压缩为 \(encoded.pixelWidth)x\(encoded.pixelHeight)，\(encoded.byteCount) 字节"
        )

        onStage?("正在生成并自检描述")
        var generated: GeneratedContent = try decode(await request(
            encoded.base64,
            AccessibilityDescriptionPrompt.chinese(preferences: preferences),
            .generated,
            0.15,
            tokenBudget(for: preferences.style)
        ))
        var candidate = try combined(generated, preferences: preferences)
        let requiresIndependentReview = preferences.alwaysRunIndependentReview
            || generated.needsReview
            || !generated.uncertainties.isEmpty

        guard requiresIndependentReview else { return candidate }
        onStage?("检测到疑点，正在独立视觉校对")
        var review: ReviewContent = try decode(await request(
            encoded.base64,
            AccessibilityDescriptionPrompt.review(preferences: preferences,
                                                   candidate: candidate),
            .review,
            0,
            180
        ))
        if review.approved { return candidate }

        let issues = review.issues.isEmpty ? ["独立校对判定存在实质问题"] : review.issues
        onStage?("校对未通过，正在定向修正")
        generated = try decode(await request(
            encoded.base64,
            AccessibilityDescriptionPrompt.revision(preferences: preferences,
                                                     candidate: candidate,
                                                     issues: issues),
            .generated,
            0.1,
            tokenBudget(for: preferences.style)
        ))
        candidate = try combined(generated, preferences: preferences)
        onStage?("正在复核修正结果")
        review = try decode(await request(
            encoded.base64,
            AccessibilityDescriptionPrompt.review(preferences: preferences,
                                                   candidate: candidate),
            .review,
            0,
            180
        ))
        guard review.approved else {
            let finalIssues = review.issues.isEmpty ? issues : review.issues
            throw OllamaError.reviewRejected(finalIssues.joined(separator: "；"))
        }
        return candidate
    }

    private func tokenBudget(for style: DescriptionStyle) -> Int {
        switch style {
        case .low: return 220
        case .medium: return 360
        case .high: return 520
        case .photographer: return 560
        }
    }

    private func combined(_ generated: GeneratedContent,
                          preferences: DescriptionPreferences) throws -> String {
        var result = AccessibilityDescriptionPrompt.sanitize(generated.description)
        let advice = AccessibilityDescriptionPrompt.sanitize(generated.advice)
        if preferences.includeCaptureAdvice && generated.isPhoto {
            guard !advice.isEmpty else { throw OllamaError.missingCaptureAdvice }
            result += " 下次拍摄建议：\(advice)"
        }
        guard !result.isEmpty else { throw OllamaError.emptyDescription }
        return result
    }

    private func decode<T: Decodable>(_ content: String) throws -> T {
        for candidate in structuredCandidates(from: content) {
            if let decoded = try? JSONDecoder().decode(T.self, from: Data(candidate.utf8)) {
                return decoded
            }
        }
        AppLogger.shared.error("MLX 结构化响应解析失败；响应长度 \(content.utf8.count) 字节")
        throw OllamaError.malformedStructuredOutput
    }

    private func structuredCandidates(from content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var values = [trimmed]
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 3 {
                values.append(lines.dropFirst().dropLast().joined(separator: "\n"))
            }
        }
        if let first = trimmed.firstIndex(of: "{"),
           let last = trimmed.lastIndex(of: "}"), first <= last {
            values.append(String(trimmed[first...last]))
        }
        return Array(Set(values))
    }
}
