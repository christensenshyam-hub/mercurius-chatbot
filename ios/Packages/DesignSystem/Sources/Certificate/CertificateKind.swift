import Foundation

/// The two printable certificates (the founder's "B · Laurel" designs,
/// `docs/certificate/design/`):
/// - `deepDive`: the 8-unit Mercurius AI Literacy Course (`Laurel.dc.html`);
/// - `basics`: the beginner course, AI Basics (`LaurelBasics.dc.html`).
public enum CertificateKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case deepDive
    case basics

    public var id: String { rawValue }

    /// The course in prose and for VoiceOver: "Certificate of Completion,
    /// AI Literacy Course, awarded to …".
    public var courseName: String {
        switch self {
        case .deepDive: return "AI Literacy Course"
        case .basics: return "AI Basics"
        }
    }

    /// The PDF's file name (no name in it: the file may be shared).
    public var fileName: String {
        switch self {
        case .deepDive: return "Mercurius Certificate - AI Literacy Course.pdf"
        case .basics: return "Mercurius Certificate - AI Basics.pdf"
        }
    }
}

/// The words on each certificate, exactly as the designs set them. The
/// paragraphs are fixed copy, so their line breaks are fixed too: these are
/// the breaks Chrome's `text-wrap: balance` chose for the designs (measured
/// in `docs/certificate/NOTES.md`).
public enum CertificateCopy {
    public static let wordmark = "Mercurius AI"
    public static let title = "Certificate of Completion"
    public static let presentedTo = "is proudly presented to"
    public static let dateLabel = "Date"
    public static let footer = "Mercurius is made by the Mayo AI Literacy Club · trymercurius.com"
    /// Shown in the name's place while the learner hasn't typed one (the
    /// preview only; a certificate is never made without a name).
    public static let namePlaceholder = "Your Name"

    /// AI Basics' line under the title (the Deep dive has an ornament there).
    public static let basicsSubtitle = "AI Basics"

    public static func paragraphLines(_ kind: CertificateKind) -> [String] {
        switch kind {
        case .deepDive:
            return [
                "for completing the Mercurius AI Literacy Course: eight units, thirty-five lessons and",
                "eight mastery checks on how AI works, where it goes wrong, and how to use it well."
            ]
        case .basics:
            return [
                "for completing AI Basics with Mercurius, a beginner\u{2019}s course",
                "in using AI chatbots safely, clearly and with confidence."
            ]
        }
    }

    /// The Deep dive's two lines of unit names (none on AI Basics).
    public static func unitLines(_ kind: CertificateKind) -> [String] {
        switch kind {
        case .deepDive:
            return [
                "How AI Works · Bias & Fairness · AI in Society · Prompting",
                "Ethics & Alignment · Spotting AI · Using AI Well · The Frontier"
            ]
        case .basics:
            return []
        }
    }

    /// The words around the seal.
    public static func sealRing(_ kind: CertificateKind) -> String {
        switch kind {
        case .deepDive: return "MERCURIUS AI · AI LITERACY COURSE ·"
        case .basics: return "MERCURIUS AI · AI BASICS · MERCURIUS AI · AI BASICS ·"
        }
    }

    /// Who signs: a teacher or club advisor (Deep dive), an instructor or
    /// family member (AI Basics, whose learners are often adults).
    public static func signatureLabel(_ kind: CertificateKind) -> [String] {
        switch kind {
        case .deepDive:
            return ["Teacher or club advisor"]
        case .basics:
            // The design's 250 px column wraps this label after "Family".
            return ["Instructor or family", "member"]
        }
    }

    /// The date as the certificate prints it: "October 21, 2026" (US
    /// English, like the rest of the page).
    public static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }

    /// What VoiceOver reads for a certificate (the preview and the card):
    /// "Certificate of Completion, AI Literacy Course, awarded to Alexandria
    /// Montgomery-Vasquez, October 21, 2026".
    public static func accessibilitySummary(kind: CertificateKind, name: String, dateText: String?) -> String {
        let trimmed = CertificateNameFit.normalized(name)
        var parts = [title, kind.courseName]
        parts.append(trimmed.isEmpty ? "awaiting your name" : "awarded to \(trimmed)")
        if let dateText, !dateText.isEmpty { parts.append(dateText) }
        return parts.joined(separator: ", ")
    }
}
