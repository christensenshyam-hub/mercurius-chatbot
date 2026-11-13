import Testing
import SwiftUI
@testable import DesignSystem

@Suite("Motion tokens")
struct MotionTests {

    @Test("Durations are the agreed values, fastest to slowest")
    func durations() {
        #expect(Motion.Duration.fast == 0.15)
        #expect(Motion.Duration.standard == 0.25)
        #expect(Motion.Duration.slow == 0.4)
    }

    @Test("Stagger steps by 0.06 s and never goes negative")
    func stagger() {
        #expect(Motion.staggerInterval == 0.06)
        #expect(Motion.staggerDelay(0) == 0)
        #expect(abs(Motion.staggerDelay(3) - 0.18) < 1e-9)
        #expect(Motion.staggerDelay(-2) == 0)
    }

    @Test("The ambient loops keep the path's current timing")
    func ambientLoops() {
        let pulse: Animation = .easeOut(duration: 1.4).repeatForever(autoreverses: false)
        let bob: Animation = .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
        #expect(Motion.ambientPulse == pulse)
        #expect(Motion.ambientBob == bob)
    }

    @Test("Without Reduce Motion, every form returns the animation itself")
    func passesThrough() {
        let a: Animation = .easeOut(duration: Motion.Duration.standard)
        #expect(Motion.resolved(a, reduceMotion: false) == a)
        #expect(Motion.resolved(a, reduceMotion: false, fallback: .fade) == a)
        #expect(Motion.resolved(a, reduceMotion: false, fallback: .none) == a)
    }

    @Test("Under Reduce Motion, the call site chooses a 0.2 s fade or nothing")
    func reduceMotion() {
        let a: Animation = .easeOut(duration: Motion.Duration.standard)
        let fade: Animation = .easeInOut(duration: 0.2)
        #expect(Motion.fade == fade)
        #expect(Motion.resolved(a, reduceMotion: true) == fade)
        #expect(Motion.resolved(a, reduceMotion: true, fallback: .fade) == fade)
        #expect(Motion.resolved(a, reduceMotion: true, fallback: .none) == nil)
    }

    @Test("A sequential Reduce Motion fade is two 0.1 s halves of the 0.2 s fade")
    func fadeHalves() {
        #expect(Motion.fadeHalfDuration == 0.1)
        #expect(Motion.fadeHalf == .easeInOut(duration: 0.1))
    }

    @Test("Each haptic maps to its SwiftUI feedback")
    func haptics() {
        #expect(Haptic.allCases.count == 4)
        #expect(Haptic.selection.feedback == .selection)
        #expect(Haptic.success.feedback == .success)
        #expect(Haptic.warning.feedback == .warning)
        #expect(Haptic.lightImpact.feedback == .impact(weight: .light))
    }
}
