import Foundation

enum MLXVLMError: LocalizedError {
    case invalidResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "MLX 本地模型返回了无法识别的响应"
        case let .server(code, message): return "MLX 本地服务错误 \(code)：\(message)"
        }
    }
}

struct MLXVLMClient {
    private struct ImageURLValue: Encodable {
        let url: String
    }

    private struct ContentPart: Encodable {
        let type: String
        var text: String?
        var imageURL: ImageURLValue?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
    }

    private struct Message: Encodable {
        let role: String
        let content: [ContentPart]
    }

    private struct JSONSchemaEnvelope: Encodable {
        let name = "PhotoAccessibilityDescription"
        let strict = true
        let schema: VisionJSONSchema
    }

    private struct ResponseFormat: Encodable {
        let type = "json_schema"
        let jsonSchema: JSONSchemaEnvelope

        enum CodingKeys: String, CodingKey {
            case type
            case jsonSchema = "json_schema"
        }
    }

    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let responseFormat: ResponseFormat
        let maximumTokens: Int
        let temperature: Double
        let topP: Double
        let stream = false
        let enableThinking = false

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature, stream
            case responseFormat = "response_format"
            case maximumTokens = "max_tokens"
            case topP = "top_p"
            case enableThinking = "enable_thinking"
        }
    }

    private struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?

            enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
            }
        }
        let choices: [Choice]
        let usage: Usage?
    }

    let model: VisionModel
    let endpoint: URL
    let imageEncoder: ImageEncoder
    let requestTimeout: TimeInterval
    let retryCount: Int
    let maximumImageDimension: CGFloat

    init(model: VisionModel,
         endpoint: URL = URL(string: "http://127.0.0.1:11435/v1/chat/completions")!,
         imageEncoder: ImageEncoder = .init(),
         requestTimeout: TimeInterval = 240,
         retryCount: Int = 2,
         maximumImageDimension: CGFloat = 1280) {
        self.model = model
        self.endpoint = endpoint
        self.imageEncoder = imageEncoder
        self.requestTimeout = requestTimeout
        self.retryCount = retryCount
        self.maximumImageDimension = maximumImageDimension
    }

    func describe(_ imageURL: URL,
                  preferences: DescriptionPreferences,
                  onStage: ((String) -> Void)? = nil) async throws -> String {
        let pipeline = VisionDescriptionPipeline(imageEncoder: imageEncoder,
                                                 maximumImageDimension: maximumImageDimension)
        return try await pipeline.describe(imageURL,
                                           preferences: preferences,
                                           onStage: onStage) {
            image, prompt, schema, temperature, maximumTokens in
            try await requestContent(image: image,
                                     prompt: prompt,
                                     schema: schema,
                                     temperature: temperature,
                                     maximumTokens: maximumTokens)
        }
    }

    private func requestContent(image: String,
                                prompt: String,
                                schema: VisionJSONSchema,
                                temperature: Double,
                                maximumTokens: Int) async throws -> String {
        let body = RequestBody(
            model: RuntimePaths.mlxModelDirectory(for: model.mlxName).path,
            messages: [Message(role: "user", content: [
                ContentPart(type: "text", text: prompt, imageURL: nil),
                ContentPart(type: "image_url", text: nil,
                            imageURL: ImageURLValue(url: "data:image/jpeg;base64,\(image)"))
            ])],
            responseFormat: ResponseFormat(jsonSchema: JSONSchemaEnvelope(schema: schema)),
            maximumTokens: maximumTokens,
            temperature: temperature,
            topP: 0.85
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        var lastError: Error?
        for attempt in 0..<retryCount {
            do {
                let started = Date()
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw MLXVLMError.invalidResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "未知错误"
                    let error = MLXVLMError.server(http.statusCode, String(message.prefix(500)))
                    if http.statusCode == 429 || http.statusCode >= 500 { throw error }
                    throw NonRetryableError(underlying: error)
                }
                let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
                guard let content = decoded.choices.first?.message.content else {
                    throw MLXVLMError.invalidResponse
                }
                AppLogger.shared.log(String(
                    format: "MLX 模型调用 %.2f 秒（输入 %d token，输出 %d token）",
                    Date().timeIntervalSince(started),
                    decoded.usage?.promptTokens ?? 0,
                    decoded.usage?.completionTokens ?? 0
                ))
                return content
            } catch let error as NonRetryableError {
                throw error.underlying
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                if attempt + 1 < retryCount {
                    try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 750_000_000)
                }
            }
        }
        throw lastError ?? MLXVLMError.invalidResponse
    }

    private struct NonRetryableError: Error {
        let underlying: Error
    }
}
