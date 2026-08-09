import Foundation

struct AppConfiguration {
    var ollamaEndpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    var modelName = "qwen3.5:4b"
    var requestTimeout: TimeInterval = 180
    var retryCount = 3
    var descriptionReviewAttempts = 3
    var maximumImageDimension: CGFloat = 1600

    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"
    ]
}
