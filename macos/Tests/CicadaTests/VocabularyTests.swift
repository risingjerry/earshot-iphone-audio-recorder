import Foundation
import Testing
@testable import Cicada

@MainActor @Suite struct VocabularyTests {
    @Test func importLinesWithHeardForms() {
        let v = Vocabulary(url: nil)
        let r = v.importText("Uniswap V3\nMorpho = 莫拉、莫法\n\n" + String(repeating: "长", count: 41) + "\n巡检=寻检,巡练")
        #expect(r == .init(added: 3, updated: 0, skipped: [4]))
        #expect(v.knows(heard: "莫法", word: "morpho"))
        #expect(v.terms.first { $0.word == "巡检" }?.heard == ["寻检", "巡练"])
    }

    @Test func sameWordWhateverWidthOrCase() {
        let v = Vocabulary(url: nil)
        _ = v.importText("Aave")
        let r = v.importText("ＡＡＶＥ = 阿韦")
        #expect(r.updated == 1 && r.added == 0)
        #expect(v.terms.count == 1)
        #expect(v.knows(heard: "阿韦", word: "Aave"))
    }

    @Test func confirmAndForget() {
        let v = Vocabulary(url: nil)
        v.confirm(heard: "开布特", word: "Curve")
        #expect(v.terms == [.init(word: "Curve", heard: ["开布特"], source: "live")])
        v.forget(heard: "开布特", word: "Curve")
        #expect(!v.knows(heard: "开布特", word: "Curve"))
    }

    @Test func promptPutsRecentFirst() {
        let v = Vocabulary(url: nil)
        _ = v.importText("A\nB = b")
        v.used("B", at: Date(timeIntervalSince1970: 100))
        #expect(v.promptLines() == ["B (heard as b)", "A"])
    }

    @Test func savesAndLoads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vocab-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let v = Vocabulary(url: url)
        _ = v.importText("Morpho = 莫拉")
        #expect(Vocabulary(url: url).knows(heard: "莫拉", word: "Morpho"))
    }
}
