import Testing
import CoreGraphics
@testable import DesignSystem

/// AUD-52: in the "Nailed it!" pose Merc's raised arm turned about a point in
/// the empty gap between his head and his toga, so it floated loose beside
/// his head. The arm now turns about a shoulder inside the toga.
@Suite("Merc's arm")
struct MercArmPoseTests {

    /// The toga's silhouette in the 160×180 art: x 52…108, y 94…156, with
    /// 22 pt top corners (`Merc.swift`, "Torso / toga").
    private func insideToga(_ p: CGPoint) -> Bool {
        let minX: CGFloat = 52, maxX: CGFloat = 108, minY: CGFloat = 94, maxY: CGFloat = 156
        let radius: CGFloat = 22
        guard p.x >= minX, p.x <= maxX, p.y >= minY, p.y <= maxY else { return false }
        // Top corners: inside the corner circle when within its square.
        if p.y < minY + radius {
            if p.x > maxX - radius {
                let c = CGPoint(x: maxX - radius, y: minY + radius)
                return hypot(p.x - c.x, p.y - c.y) <= radius
            }
            if p.x < minX + radius {
                let c = CGPoint(x: minX + radius, y: minY + radius)
                return hypot(p.x - c.x, p.y - c.y) <= radius
            }
        }
        return true
    }

    @Test("The celebrating arm turns about a shoulder inside the toga")
    func celebrateShoulderIsOnTheBody() {
        let pose = MercArmPose.pose(for: .celebrate)
        #expect(insideToga(pose.shoulder))
        // The arm's rounded end (a half-circle, half its width across) is
        // inside the toga too, so no gap shows between arm and body at any
        // angle.
        let r = MercArmPose.width / 2
        for step in 0..<16 {
            let a = Double(step) * .pi / 8
            let p = CGPoint(x: pose.shoulder.x + r * cos(a), y: pose.shoulder.y + r * sin(a))
            #expect(insideToga(p), "cap point \(p) is off the toga")
        }
        // The old pivot sat outside the body: that was the floating arm.
        #expect(!insideToga(MercArmPose.restingShoulder))
        // Drawn behind the toga, so the root is hidden and the arm comes
        // out from under it.
        #expect(pose.behindTorso)
    }

    @Test("The cheer raises the arm beside his head, and it stays inside the art")
    func celebrateSwing() {
        let pose = MercArmPose.pose(for: .celebrate)
        let raised = pose.hand(at: pose.swing)
        let lowered = pose.hand(at: pose.rest)
        #expect(raised.y < pose.shoulder.y - 20, "the swing should lift the hand well above the shoulder")
        #expect(raised.x > 108 + MercArmPose.width / 2, "the raised arm should clear the head's right edge")
        #expect(lowered.y > pose.shoulder.y, "the rest end of the pump hangs below the shoulder")
        for hand in [raised, lowered] {
            #expect(hand.x + MercArmPose.width / 2 <= 160)
            #expect(hand.y - MercArmPose.width / 2 >= 0)
            #expect(hand.y + MercArmPose.width / 2 <= 180)
        }
    }

    @Test("Every other pose keeps the arm where it always hung, so their art is unchanged")
    func otherPosesUnchanged() {
        for state in MercState.allCases where state != .celebrate {
            #expect(MercArmPose.pose(for: state).shoulder == MercArmPose.restingShoulder)
            #expect(!MercArmPose.pose(for: state).behindTorso)
        }
        #expect(MercArmPose.restingShoulder == CGPoint(x: 103 + 6.5, y: 86))
        #expect(MercArmPose.pose(for: .wave) ==
                MercArmPose(shoulder: MercArmPose.restingShoulder, rest: 14, swing: -22, dur: 0.35, oscillates: true))
        #expect(MercArmPose.pose(for: .idle).oscillates == false)
    }

    @Test("Rotation follows SwiftUI: positive turns the hanging arm toward the viewer's left")
    func handGeometry() {
        let pose = MercArmPose.pose(for: .idle)
        let down = pose.hand(at: 0)
        #expect(abs(down.x - pose.shoulder.x) < 0.001)
        #expect(abs(down.y - (pose.shoulder.y + MercArmPose.length)) < 0.001)
        #expect(pose.hand(at: 90).x < pose.shoulder.x - 40)
        #expect(pose.hand(at: -90).x > pose.shoulder.x + 40)
    }
}
