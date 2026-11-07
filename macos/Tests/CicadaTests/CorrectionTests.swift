import Foundation
import Testing
@testable import Cicada

/// Cases from a 21-minute meeting recording (a DeFi team's weekly), labelled by reading the context.
@Suite struct CorrectionTests {
    private func verdict(_ from: String, _ to: String, _ c: Double, known: [(String, String)] = [],
                         rejected: [(String, String)] = []) -> Correction.Verdict {
        Correction.decide(.init(from: from, to: to, confidence: c),
                          known: { a, b in known.contains { $0 == (a, b) } },
                          rejected: { a, b in rejected.contains { $0 == (a, b) } })
    }

    @Test func soundAlikeChineseIsApplied() {
        #expect(verdict("解除质压", "解除质押", 0.9) == .apply)
        #expect(verdict("跳便是", "跳变", 0.9) != .apply)      // a word dropped: not a sound fix
        #expect(verdict("两个代笔", "两个代币", 0.9) == .apply)
        #expect(verdict("管理房", "管理方", 0.9) == .apply)
        #expect(verdict("追压", "质押", 0.85) == .apply)
        // Only the changed part is compared: 花/概 share nothing, though the phrase around them does.
        #expect(verdict("花了大花", "花了大概", 0.85) == .drop)
        #expect(verdict("FFT制押", "FFT质押", 0.9) == .apply)
    }

    @Test func confidentButUnlikeSoundIsDropped() {
        #expect(verdict("快销", "区块", 0.85) == .drop)
        #expect(verdict("苍蝇", "方向", 0.85) == .drop)
        #expect(verdict("机录", "机会", 0.8) == .drop)
    }

    @Test func lowConfidenceIsDropped() {
        #expect(verdict("质压", "质押", 0.5) == .drop)
    }

    @Test func spellingFixNeedsHighConfidence() {
        #expect(verdict("cransfer", "transfer", 0.85) == .apply)
        #expect(verdict("cransfer", "transfer", 0.7) == .drop)
        #expect(verdict("bos", "BOS", 0.9) == .drop)         // case only
    }

    @Test func newNamesAreAsked() {
        #expect(verdict("莫拉", "Morpho", 0.85) == .ask)
        #expect(verdict("开布特", "Curve", 0.8) == .ask)
        #expect(verdict("Ero", "Euler", 0.85) == .ask)
        #expect(verdict("莫纳", "Morpho", 0.7) == .drop)
    }

    @Test func confirmedHeardFormIsApplied() {
        #expect(verdict("莫拉", "Morpho", 0.5, known: [("莫拉", "Morpho")]) == .apply)
        #expect(verdict("解释这个莫拉的", "解释这个Morpho的", 0.5, known: [("莫拉", "Morpho")]) == .apply)
    }

    @Test func rejectedIsDropped() {
        #expect(verdict("质压", "质押", 0.95, rejected: [("质压", "质押")]) == .drop)
        #expect(verdict("莫拉", "Morpho", 0.95, known: [("莫拉", "Morpho")], rejected: [("莫拉", "Morpho")]) == .drop)
    }

    @Test func coreDropsSharedEnds() {
        #expect(Correction.core("解除质压", "解除质押") == ("质压", "质押"))
        #expect(Correction.core("Un450P三", "Uniswap V3") == ("Un450P三", "Uniswap V3"))
        #expect(Correction.core("解释这个莫拉的", "解释这个Morpho的") == ("莫拉", "Morpho"))
        #expect(Correction.core("找了cransfer记录", "找了transfer记录") == ("cransfer", "transfer"))
        // A Chinese change next to a Latin word leaves the word out.
        #expect(Correction.core("FFT制押", "FFT质押") == ("制押", "质押"))
        #expect(Correction.core("Un450P三", "Uniswap V3") == ("Un450P三", "Uniswap V3"))
    }

    @Test func applyReplacesAndMarks() {
        let fixes = [LineFix(from: "莫拉", to: "Morpho"), LineFix(from: "质压", to: "质押"),
                     LineFix(from: "开布特", to: "Curve", ask: true), LineFix(from: "ropax", to: "RoPax", off: true)]
        let (text, marks) = Correction.apply(fixes, to: "解释这个莫拉的，质压和开布特，ropax")
        #expect(text == "解释这个Morpho的，质押和开布特，ropax")
        #expect(marks.map { String(text[$0]) } == ["Morpho", "质押"])
    }

    @Test func applyKeepsEarlierMarksWhenLaterFixesShift() {
        let (text, marks) = Correction.apply([LineFix(from: "质压", to: "质押"), LineFix(from: "莫拉", to: "Morpho")],
                                             to: "莫拉说质压")
        #expect(text == "Morpho说质押")
        #expect(marks.map { String(text[$0]) } == ["Morpho", "质押"])
    }

    @Test func fixWhoseWordsWentAwayIsSkipped() {
        // The record recognizer rewrote the line: the fix no longer applies, nothing breaks.
        #expect(Correction.apply([LineFix(from: "莫拉", to: "Morpho")], to: "解释这个摩托的").text == "解释这个摩托的")
    }

    @Test func parseReply() {
        let reply = """
        {"translation": "I explained Morpho.", "fixes": [{"from": "莫拉", "to": "Morpho", "confidence": 0.85},
         {"from": "不在原文", "to": "x", "confidence": 0.9}]}
        """
        let p = Correction.parse(reply, subtitle: "解释这个莫拉的。")
        #expect(p?.translation == "I explained Morpho.")
        #expect(p?.edits == [.init(from: "莫拉", to: "Morpho", confidence: 0.85)])
        #expect(Correction.parse("I explained Mora.", subtitle: "x") == nil)
        #expect(Correction.parse("```json\n{\"translation\": \"Hi\"}\n```", subtitle: "x")?.translation == "Hi")
    }

    @Test func mergeKeepsRefusals() {
        let old = [LineFix(from: "莫拉", to: "Morpho", off: true), LineFix(from: "质压", to: "质押")]
        let new = [LineFix(from: "莫拉", to: "Morpho"), LineFix(from: "寻检", to: "巡检")]
        #expect(Correction.merge(old, new) == [LineFix(from: "莫拉", to: "Morpho", off: true), LineFix(from: "寻检", to: "巡检")])
    }

    @Test func recordFormatUnchangedWithoutFixes() throws {
        let line = TranscriptLine(id: "1", t: 0, speaker: "them", src: "a", dst: nil, srcLang: "zh", dstLang: "en")
        let json = String(data: try JSONEncoder().encode(line), encoding: .utf8)!
        #expect(!json.contains("fixes"))
        var fixed = line
        fixed.fixes = [LineFix(from: "a", to: "b")]
        let back = try JSONDecoder().decode(TranscriptLine.self, from: JSONEncoder().encode(fixed))
        #expect(back.shown == "b")
        #expect(back.src == "a")
    }
}
