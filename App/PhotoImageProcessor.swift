import Foundation
import ImageIO
import UniformTypeIdentifiers

enum PhotoImageProcessor {
    static let maximumInputBytes = 25 * 1_024 * 1_024
    static let maximumOutputBytes = 4 * 1_024 * 1_024
    static let maximumPixelDimension = 1_600

    /// Decode a bounded thumbnail rather than the full-resolution image. Only
    /// pixels are written to the new JPEG; source EXIF/GPS metadata is not copied.
    static func jpeg(from data: Data) throws -> Data {
        guard !data.isEmpty else { throw PhotoImageError.unreadable }
        guard data.count <= maximumInputBytes else { throw PhotoImageError.inputTooLarge }
        try Task.checkCancellation()

        return try autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
                  CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, sourceOptions) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw PhotoImageError.unreadable
            }
            let pixelWidth = width.doubleValue
            let pixelHeight = height.doubleValue
            guard pixelWidth.isFinite, pixelHeight.isFinite, pixelWidth > 0, pixelHeight > 0,
                  pixelWidth <= 40_000, pixelHeight <= 40_000,
                  pixelWidth * pixelHeight <= 200_000_000 else {
                throw PhotoImageError.dimensionsTooLarge
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
                  image.width <= maximumPixelDimension, image.height <= maximumPixelDimension else {
                throw PhotoImageError.unreadable
            }
            try Task.checkCancellation()

            for quality in [0.86, 0.72, 0.56, 0.40] {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw PhotoImageError.encoding
                }
                let outputOptions: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: quality,
                    kCGImagePropertyOrientation: 1
                ]
                CGImageDestinationAddImage(destination, image, outputOptions as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw PhotoImageError.encoding }
                try Task.checkCancellation()
                if output.length > 0 && output.length <= maximumOutputBytes { return output as Data }
            }
            throw PhotoImageError.outputTooLarge
        }
    }
}

enum PhotoImageError: Error, LocalizedError {
    case inputTooLarge
    case dimensionsTooLarge
    case unreadable
    case encoding
    case outputTooLarge

    var errorDescription: String? {
        switch self {
        case .inputTooLarge:
            return "写真のファイルサイズが25 MBを超えています。小さな写真を選ぶか、撮り直してください。"
        case .dimensionsTooLarge:
            return "写真の画素数が大きすぎます。小さな写真を選ぶか、撮り直してください。"
        case .unreadable:
            return "写真を読み込めませんでした。別の写真を選ぶか、撮り直してください。"
        case .encoding:
            return "送信用の写真を作成できませんでした。別の写真でお試しください。"
        case .outputTooLarge:
            return "写真を送信できるサイズに調整できませんでした。別の写真でお試しください。"
        }
    }
}
