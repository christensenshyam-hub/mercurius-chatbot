import SwiftUI

/// A deterministic star field: the same stars every launch (screenshots stay
/// stable), placed as fractions of the size so a resize doesn't reshuffle
/// them. Never animated. Night Studio's canvas and meaning sky on the Mac,
/// and the iPhone's night-sky card for Lesson 1.1's interactive.
public struct NightStarField: View {
    private let count: Int
    private let brightness: Double

    public init(count: Int, brightness: Double = 1) {
        self.count = max(count, 0)
        self.brightness = brightness
    }

    public var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            let width = Double(size.width)
            let height = Double(size.height)
            for _ in 0..<count {
                let x = next() * width
                let y = next() * height
                let r = 0.4 + next() * 1.0
                let a = (0.08 + next() * 0.24) * brightness
                let rect = CGRect(x: CGFloat(x - r), y: CGFloat(y - r), width: CGFloat(r * 2), height: CGFloat(r * 2))
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
