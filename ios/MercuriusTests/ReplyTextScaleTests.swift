import XCTest
import SwiftUI
import UIKit
@testable import ChatFeature

/// Merc's reply text must grow with Dynamic Type exactly as much as the
/// student's own text does. MarkdownUI applies Dynamic Type to its theme's
/// font size itself, so the bubble once handed it an already-scaled size and
/// the reply was scaled twice: about 1.65x too big at AX1 and 3x at AX5,
/// with words broken mid-word ("Her / e's"). A snapshot at the default size
/// can't catch that (the scale factor there is 1), so this measures how much
/// a one-line reply grows between Large and AX3 against a one-line student
/// bubble. The two are rendered by the real `MessageBubbleView` on iOS,
/// where Dynamic Type applies (the SPM tests run on macOS).
@MainActor
final class ReplyTextScaleTests: XCTestCase {

    private static let width: CGFloat = 393

    private func height(of message: ChatMessage, lessonStyle: Bool = false,
                        size: DynamicTypeSize) -> CGFloat {
        let view = MessageBubbleView(message: message, lessonStyle: lessonStyle)
            .environment(\.dynamicTypeSize, size)
            .frame(width: Self.width)
        let host = UIHostingController(rootView: view)
        host.view.frame = CGRect(x: 0, y: 0, width: Self.width, height: 2000)
        host.view.layoutIfNeeded()
        return host.sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude)).height
    }

    /// How many times taller a bubble is at `large` than at `size`.
    private func growth(_ message: ChatMessage, lessonStyle: Bool = false,
                        to size: DynamicTypeSize) -> CGFloat {
        height(of: message, lessonStyle: lessonStyle, size: size)
            / height(of: message, lessonStyle: lessonStyle, size: .large)
    }

    private let student = ChatMessage(role: .user, content: "Hi")
    private let merc = ChatMessage(role: .assistant, content: "Hi")

    func testSanityTheStudentBubbleGrowsWithDynamicType() {
        // If this fails, the host isn't applying Dynamic Type and the
        // comparisons below prove nothing.
        XCTAssertGreaterThan(growth(student, to: .accessibility3), 1.3)
    }

    func testFreeChatReplyGrowsLikeTheStudentBubble() {
        for size in [DynamicTypeSize.xxxLarge, .accessibility1, .accessibility3] {
            let reply = growth(merc, to: size)
            let own = growth(student, to: size)
            // Same text, same padding; the faces differ (Lexend vs SF), so
            // allow some slack. Scaled twice, the reply grew ~1.9x as much
            // as the student's bubble at AX3.
            XCTAssertLessThan(reply, own * 1.2,
                              "At \(size) Merc's reply grew \(reply)x but the student's bubble \(own)x")
            XCTAssertGreaterThan(reply, own * 0.8,
                                 "At \(size) Merc's reply grew only \(reply)x against \(own)x")
        }
    }

    func testLessonReplyGrowsLikeTheStudentBubble() {
        let reply = growth(merc, lessonStyle: true, to: .accessibility3)
        let own = growth(student, to: .accessibility3)
        XCTAssertLessThan(reply, own * 1.25,
                          "At AX3 the lesson reply grew \(reply)x but the student's bubble \(own)x")
    }
}
