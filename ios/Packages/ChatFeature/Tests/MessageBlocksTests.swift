import Testing
@testable import ChatFeature

/// blocks_v1 tokenizer contract (Presentation P4). The streaming rules are
/// the load-bearing part: raw tags and the ANS answer key must never render,
/// at ANY mid-stream cut point.
@Suite("BlockParser — blocks_v1 tokenizer")
struct MessageBlocksTests {

    static let goodQ = "[Q]\nWhich is a hallucination?\nA) A cited real study\nB) An invented citation\nC) A refusal\nANS: B\n[/Q]"

    @Test("plain prose is one prose block")
    func plainProse() {
        let blocks = BlockParser.parse("Just a reply. Two sentences.")
        #expect(blocks == [.prose("Just a reply. Two sentences.")])
    }

    @Test("full vocabulary parses in order")
    func fullVocabulary() {
        let text = "Hook line.\n\n[KEY]Likely is not true.[/KEY]\n\n[EX]Mata v. Avianca.[/EX]\n\n\(Self.goodQ)"
        let blocks = BlockParser.parse(text)
        #expect(blocks.count == 4)
        #expect(blocks[1] == .key("Likely is not true."))
        #expect(blocks[2] == .example("Mata v. Avianca."))
        guard case .quiz(let q) = blocks[3] else { Issue.record("expected quiz"); return }
        #expect(q.isWellFormed)
        #expect(q.stem == "Which is a hallucination?")
        #expect(q.options.count == 3)
        #expect(q.answerIndex == 1)
    }

    @Test("existing [CHECK] behavior unchanged")
    func checkStillWorks() {
        let blocks = BlockParser.parse("Teach.\n\n[CHECK]Why can't it look answers up?[/CHECK]")
        #expect(blocks == [.prose("Teach.\n\n"), .check("Why can't it look answers up?")])
    }

    @Test("ANS is never renderable at any streaming cut point")
    func ansNeverRenders() {
        let full = "Intro.\n\n\(Self.goodQ)\n\nAfter."
        for cut in 1...full.count {
            let partial = String(full.prefix(cut))
            for block in BlockParser.parse(partial) {
                if case .prose(let s) = block {
                    #expect(!s.contains("ANS"), "prose leaked ANS at cut \(cut)")
                    #expect(!s.contains("[Q]"), "raw tag leaked at cut \(cut)")
                }
            }
            #expect(!BlockParser.plainText(partial).contains("ANS:"), "plainText leaked ANS at cut \(cut)")
        }
    }

    @Test("partial trailing markers are withheld")
    func partialMarkersWithheld() {
        for partial in ["Teach [K", "Teach [KE", "Teach [/CHEC", "Teach [Q", "Teach [E"] {
            let blocks = BlockParser.parse(partial)
            #expect(blocks == [.prose("Teach ")], "\(partial) should withhold the tail")
        }
    }

    @Test("unclosed spans render interiors live")
    func unclosedSpansLive() {
        guard case .key(let k)? = BlockParser.parse("[KEY]Streaming takeaway").last else {
            Issue.record("expected live key"); return
        }
        #expect(k == "Streaming takeaway")

        guard case .quiz(let q)? = BlockParser.parse("[Q]\nStem here?\nA) one\nB) tw").last else {
            Issue.record("expected live quiz"); return
        }
        #expect(!q.isComplete)
        #expect(q.stem == "Stem here?")
        #expect(q.options.count == 2, "fully-arrived and partial option lines render")
    }

    @Test("malformed [Q] degrades: complete but not well-formed")
    func malformedQuiz() {
        let oneOption = "[Q]\nStem?\nA) only\nANS: A\n[/Q]"
        guard case .quiz(let q)? = BlockParser.parse(oneOption).last else {
            Issue.record("expected quiz"); return
        }
        #expect(q.isComplete)
        #expect(!q.isWellFormed)
    }

    @Test("plainText flattens with options and no markers")
    func plainTextShape() {
        let out = BlockParser.plainText("X.\n\n[KEY]K.[/KEY]\n\n\(Self.goodQ)")
        #expect(out.contains("K."))
        #expect(out.contains("B) An invented citation"))
        #expect(!out.contains("[KEY]"))
        #expect(!out.contains("ANS"))
    }
}
