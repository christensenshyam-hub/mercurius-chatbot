import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import DesignSystem
#if os(macOS)
import AppKit
#endif

/// The picture a student can share after passing a lesson: a 4:5 portrait card
/// (540×675pt, rendered at 2x → 1080×1350px).
///
/// Everything is pinned so the PNG is the same on every device: fixed colors
/// (the adaptive brand tokens would resolve against the renderer's trait
/// collection, not the app theme) and the rounded system face (the reading font
/// is registered at runtime and may not be available to the renderer).
struct LessonShareCard: View {
    static let pointSize = CGSize(width: 540, height: 675)
    static let renderScale: CGFloat = 2

    let lessonTitle: String
    /// "Unit 01 · Lesson 3"; nil drops the line.
    let progressLine: String?

    init(lessonTitle: String, unitLabel: String?, lessonNumber: Int?) {
        self.lessonTitle = lessonTitle
        self.progressLine = Self.progressLine(unitLabel: unitLabel, lessonNumber: lessonNumber)
    }

    /// The host passes the header's uppercase label ("UNIT 01"); the card
    /// reads in sentence case.
    static func progressLine(unitLabel: String?, lessonNumber: Int?) -> String? {
        let unit = unitLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
        let lesson = lessonNumber.map { "Lesson \($0)" }
        let parts = [unit, lesson].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let ink = Color.white
    private static let gold = Color(red: 0xE9 / 255, green: 0xC7 / 255, blue: 0x68 / 255)

    var body: some View {
        ZStack {
            Rectangle().fill(BrandGradient.merc)
            confetti

            VStack(spacing: 0) {
                Text("LESSON COMPLETE")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(Self.ink.opacity(0.9))
                    .padding(.top, 52)

                ZStack {
                    Circle()
                        .fill(Self.ink.opacity(0.14))
                        .frame(width: 250, height: 250)
                    Merc(state: .celebrate, size: 210, ambient: false)
                        .offset(y: 6)
                }
                .padding(.top, 22)

                Text(lessonTitle)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundStyle(Self.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 24)
                    .padding(.horizontal, 44)

                if let progressLine {
                    Text(progressLine)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.ink.opacity(0.85))
                        .padding(.top, 10)
                }

                Spacer(minLength: 16)

                Text("trymercurius.com/get")
                    .font(.system(size: 19, weight: .heavy, design: .rounded))
                    .foregroundStyle(BrandColor.mercViolet)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Self.ink))
                    .padding(.bottom, 44)
            }
        }
        .frame(width: Self.pointSize.width, height: Self.pointSize.height)
        .environment(\.colorScheme, .light)
    }

    /// A still burst framing Merc's halo — the mascot's own confetti only moves
    /// when animated, so the static render needs its own.
    private var confetti: some View {
        let pieces: [(x: CGFloat, y: CGFloat, angle: Double, color: Color)] = [
            (120, 150, -30, Self.gold), (420, 140, 25, Self.ink),
            (90, 260, 15, Self.ink), (455, 250, -20, Self.gold),
            (150, 330, 40, Self.gold), (395, 340, -45, Self.ink),
            (200, 110, 60, Self.ink), (345, 105, -60, Self.gold),
        ]
        return ZStack {
            ForEach(pieces.indices, id: \.self) { i in
                let piece = pieces[i]
                Capsule()
                    .fill(piece.color.opacity(0.85))
                    .frame(width: 9, height: 20)
                    .rotationEffect(.degrees(piece.angle))
                    .position(x: piece.x, y: piece.y)
            }
        }
        .frame(width: Self.pointSize.width, height: Self.pointSize.height)
    }

    // MARK: - Rendering

    /// PNG bytes for the card at 1080×1350px, or nil if the renderer fails.
    @MainActor
    func pngData() -> Data? {
        render().flatMap(Self.png(from:))
    }

    /// The card as a share-sheet item plus the thumbnail `SharePreview` shows.
    @MainActor
    func renderShareable() -> (item: LessonShareImage, preview: Image)? {
        guard let cgImage = render(), let png = Self.png(from: cgImage) else { return nil }
        return (LessonShareImage(png: png), Image(decorative: cgImage, scale: Self.renderScale))
    }

    @MainActor
    private func render() -> CGImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = Self.renderScale
        return renderer.cgImage
    }

    private static func png(from cgImage: CGImage) -> Data? {
        #if os(iOS)
        return UIImage(cgImage: cgImage).pngData()
        #elseif os(macOS)
        // macOS path exists so the SPM test host can pin the output size;
        // the app itself ships for iOS only.
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        #else
        return nil
        #endif
    }
}

/// Shares the exact rendered PNG, so the recipient gets the full 1080×1350
/// image rather than a re-rasterized `Image`.
struct LessonShareImage: Transferable, Sendable {
    let png: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("Mercurius lesson complete.png")
    }
}

#if DEBUG
#Preview("Share card") {
    LessonShareCard(
        lessonTitle: "Reward hacking & specification gaming",
        unitLabel: "UNIT 01",
        lessonNumber: 3
    )
    .scaleEffect(0.6)
}
#endif
