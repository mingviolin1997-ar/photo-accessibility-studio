import AppKit
import Foundation

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

struct ImageEncoder {
    func jpegBase64(for url: URL, maximumDimension: CGFloat) throws -> String {
        guard let image = NSImage(contentsOf: url) else { throw ImageEncoderError.cannotOpen }
        let original = image.size
        let scale = min(1, maximumDimension / max(original.width, original.height))
        let target = NSSize(width: max(1, original.width * scale),
                            height: max(1, original.height * scale))
        let rendered = NSImage(size: target)
        rendered.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target),
                   from: .zero,
                   operation: .copy,
                   fraction: 1)
        rendered.unlockFocus()
        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            throw ImageEncoderError.cannotRender
        }
        guard let data = bitmap.representation(using: .jpeg,
                                               properties: [.compressionFactor: 0.9]) else {
            throw ImageEncoderError.cannotEncode
        }
        return data.base64EncodedString()
    }
}
