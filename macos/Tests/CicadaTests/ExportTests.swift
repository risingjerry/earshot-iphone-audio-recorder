import Foundation
import Testing
@testable import Cicada

@Suite struct ExportTests {
    private func line(_ id: String, _ t: Double, _ speaker: String, _ src: String, _ dst: String?) -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: speaker, src: src, dst: dst, srcLang: "en", dstLang: "zh-CN")
    }

    private var session: Session {
        Session(id: "s", title: "Weekly", startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 600),
                lines: [line("1", 1.5, "them", "Hello.", "你好。"),
                        line("2", 3.25, "me", "Same", "Same"),
                        line("3", 20, "them", "Bye.", nil)],
                hasAudio: false, notes: nil, renamed: true)
    }

    @Test func clockFormats() {
        #expect(TranscriptExport.clock(0) == "00:00")
        #expect(TranscriptExport.clock(-5) == "00:00")
        #expect(TranscriptExport.clock(125.9) == "02:05")
        #expect(TranscriptExport.clock(3725) == "1:02:05")
    }

    @Test func srtTimesAndTranslations() {
        let srt = TranscriptExport.srt(session)
        let cues = srt.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(cues.count == 3)
        // Ends at the next line, at least 1 s and at most 8 s after it starts.
        #expect(cues[0] == "1\n00:00:01,500 --> 00:00:03,250\nHello.\n你好。")
        // A translation identical to the source isn't repeated; your own line says it was 同传.
        #expect(cues[1] == "2\n00:00:03,250 --> 00:00:11,250\n[同传] Same")
        // The last line gets 4 s.
        #expect(cues[2] == "3\n00:00:20,000 --> 00:00:24,000\nBye.")
    }

    @Test func markdownHasTitleLinesAndQuotes() {
        let md = TranscriptExport.markdown(session)
        #expect(md.hasPrefix("# Weekly\n\n"))
        #expect(md.contains("**[00:01] 对方**  \nHello.\n> 你好。\n"))
        #expect(md.contains("**[00:03] 你 · 同传**  \nSame\n\n"))
        #expect(!md.contains("> Same"))
    }
}
