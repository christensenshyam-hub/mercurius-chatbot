import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Production `ImagePreparing`. Built on ImageIO/CoreGraphics (available on
/// every Apple platform, no UIKit), so the package compiles for the macOS
/// `swift test` host too.
///
/// Pipeline: decode → generate a downscaled, orientation-baked thumbnail
/// (longest edge ≤ `maxDimension`) → JPEG-encode, stepping quality down until
/// the bytes fit under the size cap. Always emits `image/jpeg`, normalizing
/// HEIC/PNG captures to something the backend (and Claude's vision API) accept.
public struct JPEGImagePreparer: ImagePreparing {
    let maxDimension: Int
    let initialQuality: CGFloat
    let maxBytes: Int

    public init(
        maxDimension: Int = 2048,
        initialQuality: CGFloat = 0.8,
        maxBytes: Int = ImageUploadLimits.maxBytes
    ) {
        self.maxDimension = maxDimension
        self.initialQuality = initialQuality
        self.maxBytes = maxBytes
    }

    public func prepare(imageData: Data, fileName: String?) throws -> APIClient.ImageUploadInput {
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            CGImageSourceGetCount(source) > 0
        else {
            throw ImagePreparationError.unreadableImage
        }

        // One step gives us downscale + EXIF-orientation correction. MaxPixelSize
        // is a ceiling: smaller images come back at their original size (no
        // upscaling).
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImagePreparationError.unreadableImage
        }

        var quality = initialQuality
        guard var encoded = Self.encodeJPEG(cgImage, quality: quality) else {
            throw ImagePreparationError.unreadableImage
        }
        while encoded.count > maxBytes, quality > 0.3 {
            quality -= 0.15
            guard let smaller = Self.encodeJPEG(cgImage, quality: quality) else { break }
            encoded = smaller
        }

        guard !encoded.isEmpty, encoded.count <= maxBytes else {
            throw ImagePreparationError.tooLargeAfterCompression
        }

        return APIClient.ImageUploadInput(
            contentType: "image/jpeg",
            base64Data: encoded.base64EncodedString(),
            fileName: Self.jpegFileName(from: fileName)
        )
    }

    /// Encode a CGImage to JPEG `Data` at the given quality, or nil on failure.
    static func encodeJPEG(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// We always re-encode to JPEG, so force a `.jpg` extension on the metadata
    /// file name (or nil if the picker gave us none).
    static func jpegFileName(from original: String?) -> String? {
        guard let original, !original.isEmpty else { return nil }
        let base = (original as NSString).deletingPathExtension
        let safeBase = base.isEmpty ? "image" : base
        return "\(safeBase).jpg"
    }
}
