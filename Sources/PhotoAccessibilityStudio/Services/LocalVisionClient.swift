import Foundation

struct LocalVisionClient {
    let engine: InferenceEngine
    let model: VisionModel

    func describe(_ imageURL: URL,
                  preferences: DescriptionPreferences,
                  onStage: ((String) -> Void)? = nil) async throws -> String {
        switch engine {
        case .mlx:
            return try await MLXVLMClient(model: model).describe(
                imageURL,
                preferences: preferences,
                onStage: onStage
            )
        case .ollama:
            return try await OllamaClient(
                configuration: AppConfiguration(modelName: model.ollamaName)
            ).describe(imageURL, preferences: preferences, onStage: onStage)
        }
    }
}
