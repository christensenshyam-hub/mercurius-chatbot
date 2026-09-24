import SwiftUI

/// The one alert shown after a report, shared by the chat and lesson hosts so
/// their copy can't drift. Built from the real `ReportOutcome` — never shown
/// before the request has actually been answered.
struct ReportFeedback: Equatable {
    let outcome: ChatViewModel.ReportOutcome
    /// Two identical outcomes in a row are still two reports; this keeps them
    /// distinct so the second one presents its own alert.
    private let presentation = UUID()

    init(_ outcome: ChatViewModel.ReportOutcome) {
        self.outcome = outcome
    }

    var title: String {
        switch outcome {
        case .sent: return "Reported"
        case .failed: return "Couldn't send report"
        }
    }

    var message: String {
        switch outcome {
        case .sent: return "Thanks — we'll review this response."
        // The real reason: `APIError.offline` / `.timeout` already carry the
        // connection copy, and a 429/500 should not be blamed on the network.
        case .failed(let reason): return reason
        }
    }
}

private struct ReportFeedbackAlert: ViewModifier {
    let feedback: ReportFeedback?
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onChange(of: feedback) { _, new in
                if new != nil { isPresented = true }
            }
            // `feedback` is never cleared, so the copy stays put while the
            // alert animates out.
            .alert(feedback?.title ?? "", isPresented: $isPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(feedback?.message ?? "")
            }
    }
}

extension View {
    /// Presents the shared report-outcome alert each time `feedback` changes.
    func reportFeedbackAlert(_ feedback: ReportFeedback?) -> some View {
        modifier(ReportFeedbackAlert(feedback: feedback))
    }
}
