import CoreGraphics
import Foundation
import SwiftUI

/// The certificate as a one-page vector PDF (792 × 612 pt, US Letter
/// landscape): `CertificateView` drawn by `ImageRenderer` straight into a
/// Core Graphics PDF context, so the text stays text (selectable, with the
/// bundled fonts embedded as subsets) and the mark is the original 470 ×
/// 415 px image (about 730 dpi at its printed size).
///
/// Nothing here leaves the device: the data goes to the print panel, the
/// share sheet or a file the learner picks.
@MainActor
public enum CertificatePDF {
    public static func data(kind: CertificateKind, name: String, date: Date?) -> Data? {
        data(for: CertificateView(kind: kind, name: name, date: date), kind: kind)
    }

    public static func data(kind: CertificateKind, name: String, dateText: String?) -> Data? {
        data(for: CertificateView(kind: kind, name: name, dateText: dateText), kind: kind)
    }

    private static func data(for view: CertificateView, kind: CertificateKind) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(Certificate.pageSize)
        // Layout rounds to the display scale: at 8 it places text within
        // 1/8 pt of where the design puts it (1 would round to whole points).
        renderer.scale = 8
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: Certificate.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "\(CertificateCopy.title) · \(kind.courseName)",
            kCGPDFContextCreator: "Mercurius"
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            return nil
        }
        var drew = false
        renderer.render { size, draw in
            guard size.width > 0, size.height > 0 else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            drew = true
        }
        context.closePDF()
        return drew ? output as Data : nil
    }
}
