import Foundation

enum OllamaError: LocalizedError {
    case invalidResponse
    case server(Int, String)
    case emptyDescription
    case modelMissing(String)
    case missingCaptureAdvice
    case reviewRejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Ollama 返回了无法识别的响应"
        case let .server(code, message): return "Ollama 错误 \(code)：\(message)"
        case .emptyDescription: return "模型没有生成描述"
        case let .modelMissing(name): return "本机尚未安装模型 \(name)"
        case .missingCaptureAdvice: return "模型未按要求生成拍摄建议"
        case let .reviewRejected(issues): return "无障碍描述未通过自动校对：\(issues)"
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

    private struct Request: Codable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let think: Bool
        let format: String
        let options: Options
    }

    private struct Options: Codable {
        let temperature: Double
        let num_predict: Int
    }

    private struct Response: Codable {
        let message: Message
    }

    private struct GeneratedContent: Codable {
        let isPhoto: Bool
        let description: String
        let advice: String
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
        let image = try imageEncoder.jpegBase64(
            for: imageURL,
            maximumDimension: configuration.maximumImageDimension
        )
        onStage?("正在生成初稿")
        var generated: GeneratedContent = try await requestJSON(
            image: image,
            prompt: AccessibilityDescriptionPrompt.chinese(preferences: preferences),
            temperature: 0.2,
            maximumTokens: 700
        )

        for attempt in 0..<configuration.descriptionReviewAttempts {
            let candidate = try combined(generated, preferences: preferences)
            onStage?("正在进行第 \(attempt + 1) 轮独立校对")
            let review: ReviewContent = try await requestJSON(
                image: image,
                prompt: AccessibilityDescriptionPrompt.review(preferences: preferences,
                                                              candidate: candidate),
                temperature: 0.0,
                maximumTokens: 350
            )
            if review.approved { return candidate }
            let issues = review.issues.isEmpty ? ["校对模型判定描述存在实质问题"] : review.issues
            guard attempt + 1 < configuration.descriptionReviewAttempts else {
                throw OllamaError.reviewRejected(issues.joined(separator: "；"))
            }
            onStage?("校对未通过，正在根据问题重写")
            generated = try await requestJSON(
                image: image,
                prompt: AccessibilityDescriptionPrompt.revision(preferences: preferences,
                                                                candidate: candidate,
                                                                issues: issues),
                temperature: 0.15,
                maximumTokens: 700
            )
        }
        throw OllamaError.invalidResponse
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
                                           temperature: Double,
                                           maximumTokens: Int) async throws -> T {
        let body = Request(
            model: configuration.modelName,
            messages: [Message(role: "user", content: prompt, images: [image])],
            stream: false,
            think: false,
            format: "json",
            options: Options(temperature: temperature, num_predict: maximumTokens)
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
                guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
                guard (200..<300).contains(http.statusCode) else {
                    throw OllamaError.server(http.statusCode,
                        String(data: data, encoding: .utf8) ?? "未知错误")
                }
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                return try JSONDecoder().decode(T.self,
                    from: Data(decoded.message.content.utf8))
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                if attempt + 1 < configuration.retryCount {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                }
            }
        }
        throw lastError ?? OllamaError.invalidResponse
    }

    func checkHealth() async throws {
        let endpoint = URL(string: "http://127.0.0.1:11434/api/tags")!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OllamaError.invalidResponse
        }
        let tags = try JSONDecoder().decode(TagsResponse.self, from: data)
        let expected = configuration.modelName
        guard tags.models.contains(where: { $0.name == expected || $0.name.hasPrefix(expected + ":") }) else {
            throw OllamaError.modelMissing(expected)
        }
    }
}
