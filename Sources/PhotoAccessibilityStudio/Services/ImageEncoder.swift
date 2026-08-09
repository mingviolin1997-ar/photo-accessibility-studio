import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoderError: LocalizedError {
    case cannotOpen
    case cannotRender
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "无法打开图像"
        case .cannotRender: return "无法渲染图像"
        case .cannotEncode: return "无法为模型编码图像"
        }
    }
}

struct EncodedModelImage: Equatable, Sendable {
    let base64: String
    let pixelWidth: Int
    let pixelHeight: Int
    let byteCount: Int
}

struct ImageEncoder: Sendable {
    func encode(for url: URL, maximumDimension: CGFloat) throws -> EncodedModelImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary), CGImageSourceGetCount(source) > 0 else {
            throw ImageEncoderError.cannotOpen
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maximumDimension.rounded())),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageEncoderError.cannotRender
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw ImageEncoderError.cannotEncode }
        CGImageDestinationAddImage(destination, thumbnail, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageEncoderError.cannotEncode
        }
        let data = output as Data
        return EncodedModelImage(base64: data.base64EncodedString(),
                                 pixelWidth: thumbnail.width,
                                 pixelHeight: thumbnail.height,
                                 byteCount: data.count)
    }

    func jpegBase64(for url: URL, maximumDimension: CGFloat) throws -> String {
        try encode(for: url, maximumDimension: maximumDimension).base64
    }
}
