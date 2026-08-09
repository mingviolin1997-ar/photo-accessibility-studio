import Foundation

struct AppConfiguration {
    var ollamaEndpoint: URL
    var modelName: String
    var requestTimeout: TimeInterval
    var retryCount: Int
    var maximumImageDimension: CGFloat
    var keepAlive: String
    var contextWindow: Int

    init(modelName: String? = nil,
         defaults: UserDefaults = .standard) {
        ollamaEndpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
        self.modelName = modelName
            ?? defaults.string(forKey: "selectedVisionModel")
            ?? VisionModel.qwen35_4B.ollamaName
        requestTimeout = 180
        retryCount = 2
        maximumImageDimension = 1280
        keepAlive = "10m"
        contextWindow = 4096
    }

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"
    ]
}
