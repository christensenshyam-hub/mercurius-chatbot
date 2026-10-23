#if os(macOS)
import Testing
@testable import DesignSystem

/// Night's typographic pass: curly quotes in prose, code left alone.
@Suite("Night typography: curly quotes")
struct NightTypographyTests {
    @Test("Straight quotes in prose become curly, on the right side")
    func prose() {
        #expect(NightTypography.curlQuotes(#"The sentence "I went to the bank" contains one word"#)
            == "The sentence “I went to the bank” contains one word")
        #expect(NightTypography.curlQuotes(#"three tokens: "un", "believ", "able"."#)
            == "three tokens: “un”, “believ”, “able”.")
        #expect(NightTypography.curlQuotes(#"so "bank" (financial) clusters near "loan" and "deposit,""#)
            == "so “bank” (financial) clusters near “loan” and “deposit,”")
        #expect(NightTypography.curlQuotes("It doesn't really 'know' facts") == "It doesn’t really ‘know’ facts")
        #expect(NightTypography.curlQuotes(#"why "objective algorithm" is a myth."#) == "why “objective algorithm” is a myth.")
        #expect(NightTypography.curlQuotes(#"**"mostly true"** and ("always true")"#)
            == "**“mostly true”** and (“always true”)")
    }

    @Test("Code, fenced blocks and link addresses stay byte for byte; text without quotes is untouched")
    func code() {
        #expect(NightTypography.curlQuotes(#"Use `print("hi")` here, "then" go."#) == "Use `print(\"hi\")` here, “then” go.")
        let fenced = "Run:\n```\nlet s = \"x\"\n```\nDone \"now\"."
        #expect(NightTypography.curlQuotes(fenced) == "Run:\n```\nlet s = \"x\"\n```\nDone “now”.")
        #expect(NightTypography.curlQuotes(#"See [the "paper"](https://x.org/a"b) now."#)
            == #"See [the “paper”](https://x.org/a"b) now."#)
        let plain = "No quotes at all — just text."
        #expect(NightTypography.curlQuotes(plain) == plain)
    }
}
#endif
