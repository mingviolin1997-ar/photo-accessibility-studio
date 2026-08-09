import Foundation

enum OllamaError: LocalizedError {
    case invalidResponse
    case server(Int, String)
    case emptyDescription
    case modelMissing(String)
    case missingCaptureAdvice
    case reviewRejected(String)
    case malformedStructuredOutput

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "本地模型返回了无法识别的响应"
        case let .server(code, message): return "本地模型服务错误 \(code)：\(message)"
        case .emptyDescription: return "模型没有生成描述"
        case let .modelMissing(name): return "本机尚未安装模型 \(name)"
        case .missingCaptureAdvice: return "模型未按要求生成拍摄建议"
        case let .reviewRejected(issues): return "无障碍描述未通过自动校对：\(issues)"
        case .malformedStructuredOutput:
            return "模型返回的结构化描述不完整；软件没有丢弃照片，请重试这一张"
        }
    }
}

struct OllamaClient {
    private struct TagsResponse: Codable {
        struct Model: Codable { let name: String }
        let models: [Model]
    }

    private struct Message: Codable {
        let role: String
        let content: String
        var images: [String]?
    }

    private struct SchemaItems: Encodable {
        let type: String
    }

    private struct SchemaProperty: Encodable {
        let type: String
        var items: SchemaItems?

        init(_ type: String, items: SchemaItems? = nil) {
            self.type = type
            self.items = items
        }
    }

    private struct JSONSchema: Encodable {
        let type = "object"
        let properties: [String: SchemaProperty]
        let required: [String]
        let additionalProperties = false

        static let generated = JSONSchema(
            properties: [
                "isPhoto": SchemaProperty("boolean"),
                "description": SchemaProperty("string"),
                "advice": SchemaProperty("string"),
                "needsReview": SchemaProperty("boolean"),
                "uncertainties": SchemaProperty("array", items: SchemaItems(type: "string"))
            ],
            required: ["isPhoto", "description", "advice", "needsReview", "uncertainties"]
        )

        static let review = JSONSchema(
            properties: [
                "approved": SchemaProperty("boolean"),
                "issues": SchemaProperty("array", items: SchemaItems(type: "string"))
            ],
            required: ["approved", "issues"]
        )
    }

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let think: Bool
        let format: JSONSchema
        let options: Options
        let keepAlive: String

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, think, format, options
            case keepAlive = "keep_alive"
        }
    }

    private struct Options: Codable {
        let temperature: Double
        let topP: Double
        let numPredict: Int
        let numContext: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case topP = "top_p"
            case numPredict = "num_predict"
            case numContext = "num_ctx"
        }
    }

    private struct Response: Codable {
        let message: Message
        let totalDuration: Int64?
        let loadDuration: Int64?
        let promptEvalCount: Int?
        let evalCount: Int?

        enum CodingKeys: String, CodingKey {
            case message
            case totalDuration = "total_duration"
            case loadDuration = "load_duration"
            case promptEvalCount = "prompt_eval_count"
            case evalCount = "eval_count"
        }
    }

    private struct GeneratedContent: Codable {
        let isPhoto: Bool
        let description: String
        let advice: String
        let needsReview: Bool
        let uncertainties: [String]
    }

    private struct ReviewContent: Codable {
        let approved: Bool
        let issues: [String]
    }

    let configuration: AppConfiguration
    let imageEncoder: ImageEncoder

    init(configuration: AppConfiguration = .init(), imageEncoder: ImageEncoder = .init()) {
        self.configuration = configuration
        self.imageEncoder = imageEncoder
    }

    func describe(_ imageURL: URL,
                  preferences: DescriptionPreferences = .init(style: .medium,
                                                               includeCaptureAdvice: false),
                  onStage: ((String) -> Void)? = nil) async throws -> String {
        onStage?("正在节能预处理照片")
        let encoder = imageEncoder
        let dimension = configuration.maximumImageDimension
        let encoded = try await Task.detached(priority: .utility) {
            try encoder.encode(for: imageURL, maximumDimension: dimension)
        }.value
        AppLogger.shared.log(
            "模型输入已压缩为 \(encoded.pixelWidth)x\(encoded.pixelHeight)，\(encoded.byteCount) 字节"
        )

        onStage?("正在生成并自检描述")
        var generated: GeneratedContent = try await requestJSON(
            image: encoded.base64,
            prompt: AccessibilityDescriptionPrompt.chinese(preferences: preferences),
            schema: .generated,
            temperature: 0.15,
            maximumTokens: tokenBudget(for: preferences.style)
        )
        var candidate = try combined(generated, preferences: preferences)
        let requiresIndependentReview = preferences.alwaysRunIndependentReview
            || generated.needsReview
            || !generated.uncertainties.isEmpty

        guard requiresIndependentReview else { return candidate }
        onStage?("检测到疑点，正在独立视觉校对")
        var review: ReviewContent = try await requestJSON(
            image: encoded.base64,
            prompt: AccessibilityDescriptionPrompt.review(preferences: preferences,
                                                           candidate: candidate),
            schema: .review,
            temperature: 0,
            maximumTokens: 180
        )
        if review.approved { return candidate }

        let issues = review.issues.isEmpty ? ["独立校对判定存在实质问题"] : review.issues
        onStage?("校对未通过，正在定向修正")
        generated = try await requestJSON(
            image: encoded.base64,
            prompt: AccessibilityDescriptionPrompt.revision(preferences: preferences,
                                                             candidate: candidate,
                                                             issues: issues),
            schema: .generated,
            temperature: 0.1,
            maximumTokens: tokenBudget(for: preferences.style)
        )
        candidate = try combined(generated, preferences: preferences)
        onStage?("正在复核修正结果")
        review = try await requestJSON(
            image: encoded.base64,
            prompt: AccessibilityDescriptionPrompt.review(preferences: preferences,
                                                           candidate: candidate),
            schema: .review,
            temperature: 0,
            maximumTokens: 180
        )
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

    private func requestJSON<T: Decodable>(image: String,
                                           prompt: String,
                                           schema: JSONSchema,
                                           temperature: Double,
                                           maximumTokens: Int) async throws -> T {
        let body = Request(
            model: configuration.modelName,
            messages: [Message(role: "user", content: prompt, images: [image])],
            stream: false,
            think: false,
            format: schema,
            options: Options(temperature: temperature,
                             topP: 0.85,
                             numPredict: maximumTokens,
                             numContext: configuration.contextWindow),
            keepAlive: configuration.keepAlive
        )
        var request = URLRequest(url: configuration.ollamaEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        var lastError: Error?
        for attempt in 0..<configuration.retryCount {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw OllamaError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    let error = OllamaError.server(
                        http.statusCode,
                        String(data: data, encoding: .utf8) ?? "未知错误"
                    )
                    if http.statusCode == 429 || http.statusCode >= 500 {
                        throw error
                    }
                    throw NonRetryableError(underlying: error)
                }
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                logMetrics(decoded)
                return try decodeStructured(T.self, from: decoded.message.content)
            } catch let error as NonRetryableError {
                throw error.underlying
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                if attempt + 1 < configuration.retryCount {
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 750_000_000)
                }
            }
        }
        throw lastError ?? OllamaError.invalidResponse
    }

    private struct NonRetryableError: Error {
        let underlying: Error
    }

    private func decodeStructured<T: Decodable>(_ type: T.Type,
                                                 from content: String) throws -> T {
        let candidates = structuredCandidates(from: content)
        for candidate in candidates {
            if let decoded = try? JSONDecoder().decode(T.self, from: Data(candidate.utf8)) {
                return decoded
            }
        }
        AppLogger.shared.error("结构化模型响应解析失败；响应长度 \(content.utf8.count) 字节")
        throw NonRetryableError(underlying: OllamaError.malformedStructuredOutput)
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

    private func logMetrics(_ response: Response) {
        let total = Double(response.totalDuration ?? 0) / 1_000_000_000
        let load = Double(response.loadDuration ?? 0) / 1_000_000_000
        AppLogger.shared.log(
            String(format: "模型调用 %.2f 秒（加载 %.2f 秒，输入 %d token，输出 %d token）",
                   total, load, response.promptEvalCount ?? 0, response.evalCount ?? 0)
        )
    }

    func installedModelNames() async throws -> Set<String> {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/tags")!)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OllamaError.invalidResponse
        }
        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        return Set(tags.models.map(\.name))
    }

    func checkHealth() async throws {
        let installed = try await installedModelNames()
        let expected = configuration.modelName
        guard installed.contains(where: { $0 == expected || $0.hasPrefix(expected + ":") }) else {
            throw OllamaError.modelMissing(expected)
        }
    }
}
