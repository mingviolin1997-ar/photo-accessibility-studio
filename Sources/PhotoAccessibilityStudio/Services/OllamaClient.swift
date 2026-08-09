import Foundation

enum OllamaError: LocalizedError {
    case invalidResponse
    case server(Int, String)
    case emptyDescription
    case modelMissing(String)
    case missingCaptureAdvice

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Ollama 返回了无法识别的响应"
        case let .server(code, message): return "Ollama 错误 \(code)：\(message)"
        case .emptyDescription: return "模型没有生成描述"
        case let .modelMissing(name): return "本机尚未安装模型 \(name)"
        case .missingCaptureAdvice: return "模型未按要求生成拍摄建议"
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

    let configuration: AppConfiguration
    let imageEncoder: ImageEncoder

    init(configuration: AppConfiguration = .init(), imageEncoder: ImageEncoder = .init()) {
        self.configuration = configuration
        self.imageEncoder = imageEncoder
    }

    func describe(_ imageURL: URL, preferences: DescriptionPreferences = .init(style: .medium, includeCaptureAdvice: false)) async throws -> String {
        let image = try imageEncoder.jpegBase64(
            for: imageURL,
            maximumDimension: configuration.maximumImageDimension
        )
        let body = Request(
            model: configuration.modelName,
            messages: [Message(role: "user",
                               content: AccessibilityDescriptionPrompt.chinese(preferences: preferences),
                               images: [image])],
            stream: false,
            think: false,
            format: "json",
            options: Options(temperature: 0.2, num_predict: 700)
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
                let generated = try JSONDecoder().decode(GeneratedContent.self,
                    from: Data(decoded.message.content.utf8))
                var result = AccessibilityDescriptionPrompt.sanitize(generated.description)
                let advice = AccessibilityDescriptionPrompt.sanitize(generated.advice)
                if preferences.includeCaptureAdvice && generated.isPhoto {
                    guard !advice.isEmpty else { throw OllamaError.missingCaptureAdvice }
                    result += " 下次拍摄建议：\(advice)"
                }
                guard !result.isEmpty else { throw OllamaError.emptyDescription }
                return result
            } catch {
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
