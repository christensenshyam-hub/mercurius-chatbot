import Testing
import Foundation
@testable import ImageUploadFeature

// Tests for the real ImageIO-backed preparer. Runs on the macOS test host
// because it uses ImageIO/CoreGraphics (not UIKit).

private let tinyPNG = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)!

@Suite("JPEGImagePreparer")
struct JPEGImagePreparerTests {

    @Test("Re-encodes a PNG to a JPEG upload input")
    func encodesToJPEG() throws {
        let preparer = JPEGImagePreparer()
        let input = try preparer.prepare(imageData: tinyPNG, fileName: "shot.png")

        #expect(input.contentType == "image/jpeg")
        // File name extension is normalized to .jpg.
        #expect(input.fileName == "shot.jpg")

        // The base64 payload decodes to real JPEG bytes (SOI marker FF D8 FF).
        let bytes = Data(base64Encoded: input.base64Data)
        let jpeg = try #require(bytes)
        #expect(jpeg.count >= 3)
        #expect(jpeg[0] == 0xFF && jpeg[1] == 0xD8 && jpeg[2] == 0xFF)
    }

    @Test("Unreadable bytes throw .unreadableImage")
    func rejectsGarbage() {
        let preparer = JPEGImagePreparer()
        #expect(throws: ImagePreparationError.unreadableImage) {
            _ = try preparer.prepare(imageData: Data("not an image".utf8), fileName: nil)
        }
    }

    @Test("jpegFileName forces a .jpg extension, or nil")
    func fileNameNormalization() {
        #expect(JPEGImagePreparer.jpegFileName(from: "photo.heic") == "photo.jpg")
        #expect(JPEGImagePreparer.jpegFileName(from: "no-extension") == "no-extension.jpg")
        #expect(JPEGImagePreparer.jpegFileName(from: nil) == nil)
        #expect(JPEGImagePreparer.jpegFileName(from: "") == nil)
    }
}
