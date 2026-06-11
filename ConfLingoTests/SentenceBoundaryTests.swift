import Foundation
import Testing
@testable import ConfLingo

struct SentenceBoundaryTests {
    @Test func detectsBasicTerminators() {
        #expect(SentenceBoundary.endsSentence("This is a sentence."))
        #expect(SentenceBoundary.endsSentence("Is it done?"))
        #expect(SentenceBoundary.endsSentence("Amazing!"))
        #expect(SentenceBoundary.endsSentence("To be continued…"))
    }

    @Test func detectsJapaneseTerminators() {
        #expect(SentenceBoundary.endsSentence("これは文です。"))
        #expect(SentenceBoundary.endsSentence("そうですか？"))
        #expect(SentenceBoundary.endsSentence("すごい！"))
    }

    @Test func ignoresTrailingQuotesAndBrackets() {
        #expect(SentenceBoundary.endsSentence("He said \"Done.\""))
        #expect(SentenceBoundary.endsSentence("(See the note.)"))
        #expect(SentenceBoundary.endsSentence("「終わりました。」"))
    }

    @Test func ignoresTrailingWhitespace() {
        #expect(SentenceBoundary.endsSentence("Done. "))
        #expect(SentenceBoundary.endsSentence("Done.\n"))
    }

    @Test func rejectsMidSentenceFragments() {
        #expect(!SentenceBoundary.endsSentence("and then we"))
        #expect(!SentenceBoundary.endsSentence("first,"))
        #expect(!SentenceBoundary.endsSentence("note:"))
    }

    @Test func rejectsEmptyAndWhitespaceOnly() {
        #expect(!SentenceBoundary.endsSentence(""))
        #expect(!SentenceBoundary.endsSentence("   "))
        #expect(!SentenceBoundary.endsSentence("\"\""))
    }
}
