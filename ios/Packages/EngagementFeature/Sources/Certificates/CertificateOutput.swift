import Foundation
import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import PDFKit
#endif

/// One certificate to print or share: the PDF made on demand, on this
/// device.
public struct CertificateDocument: Equatable, Sendable {
    public let kind: CertificateKind
    public let name: String
    public let date: Date

    public init(kind: CertificateKind, name: String, date: Date) {
        self.kind = kind
        self.name = name
        self.date = date
    }

    @MainActor
    public func pdfData() -> Data? {
        CertificatePDF.data(kind: kind, name: name, date: date)
    }

    /// Writes the PDF to a fresh folder in the app's temporary directory
    /// (removed by `CertificateDocument.removeTemporaryFiles()` when the
    /// sheet closes) and returns its URL.
    @MainActor
    public func writeTemporaryFile() throws -> URL {
        guard let data = pdfData() else { throw CocoaError(.fileWriteUnknown) }
        let folder = Self.temporaryFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(kind.fileName)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        return url
    }

    static var temporaryFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Certificates", isDirectory: true)
    }

    /// The PDFs made for sharing carry the name: they don't outlive the
    /// sheet.
    public static func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: temporaryFolder)
    }
}

extension CertificateDocument: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { document in
            let url = try await MainActor.run { try document.writeTemporaryFile() }
            return SentTransferredFile(url)
        }
        .suggestedFileName { $0.kind.fileName }
    }
}

/// Printing, per platform: the system print panel with the PDF, landscape,
/// on the paper the printer has (Letter as is; A4 at about 97%), scaled to
/// its margins.
@MainActor
public enum CertificatePrinting {
    #if os(iOS)
    /// Shows the print sheet. Returns false when the PDF couldn't be made.
    @discardableResult
    public static func print(_ document: CertificateDocument) -> Bool {
        guard let data = document.pdfData() else { return false }
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.orientation = .landscape
        info.jobName = "Mercurius certificate"
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
        return true
    }
    #elseif os(macOS)
    /// The print panel, as a sheet on `window` (or app-modal without one).
    /// Its PDF menu also saves.
    @discardableResult
    public static func print(_ document: CertificateDocument, in window: NSWindow?) -> Bool {
        guard let data = document.pdfData(), let pdf = PDFDocument(data: data) else { return false }
        // The learner's own printer and paper (A4 stays A4): the page scales
        // to fit whatever is loaded, centred.
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.orientation = .landscape
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        guard let operation = pdf.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else {
            return false
        }
        operation.jobTitle = "Mercurius certificate"
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
        return true
    }

    /// "Save as PDF…": the save panel, as a sheet on `window`, then the PDF
    /// written where the learner chose.
    public static func save(_ document: CertificateDocument, in window: NSWindow?,
                            completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = document.kind.fileName
        panel.title = "Save Certificate"
        panel.prompt = "Save"
        let finish: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let data = document.pdfData() else {
                completion(false)
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                completion(true)
            } catch {
                completion(false)
            }
        }
        if let window {
            panel.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { finish(response) }
            }
        } else {
            finish(panel.runModal())
        }
    }
    #endif
}
