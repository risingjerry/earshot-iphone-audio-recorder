import Foundation

/// 改正听错的词, between the translation chain and the records: which fixes a line takes, which wait
/// for the user (待确认), and what the user's answers teach the word list. UI-free; the app shows
/// `pending` and passes taps back.
@MainActor
final class LiveFixes {
    let store: SessionStore
    let vocabulary: Vocabulary
    let settings: AppSettings
    /// The line changed: the app refreshes the subtitle bar if it is still showing it.
    var onLineFixed: ((_ session: String, _ line: TranscriptLine) -> Void)?
    var onChange: (() -> Void)?

    /// Fixes said no to in this meeting ("from→to"), and how often each heard form was turned down
    /// overall this run: twice and it leaves the word list.
    private var refused: Set<String> = []
    private var refusals: [String: Int] = [:]

    init(store: SessionStore, vocabulary: Vocabulary, settings: AppSettings) {
        self.store = store
        self.vocabulary = vocabulary
        self.settings = settings
    }

    func meetingStarted() { refused = [] }

    private static func pair(_ a: String, _ b: String) -> String { a + "\u{1F}" + b }

    /// What a finished sentence's request carries; nil while fixing is off.
    func context(for text: String) -> TranslationService.FixContext? {
        guard settings.fixMisheard else { return nil }
        var topic: String?
        var recent: [String] = []
        if let (id, line) = store.lineHeard(as: text), let s = store.session(id) {
            topic = s.notes?.title ?? (s.renamed == true ? s.title : nil)
            if let i = s.lines.firstIndex(where: { $0.id == line.id }) {
                recent = s.lines[max(0, i - 3)..<i].map(\.shown)
            }
        }
        return .init(topic: topic, words: vocabulary.promptLines(), recent: recent)
    }

    /// The service's proposals for a line heard as `text`.
    func received(_ text: String, _ edits: [Correction.Edit]) {
        guard settings.fixMisheard, let (id, line) = store.lineHeard(as: text) else { return }
        var fresh: [LineFix] = []
        for e in edits {
            let verdict = Correction.decide(e, known: { self.vocabulary.knows(heard: $0, word: $1) },
                                            rejected: { self.refused.contains(Self.pair($0, $1)) })
            debugLog("fix \(verdict) c=\(String(format: "%.2f", e.confidence)) line=\(line.id)")
            contentLog("FIX \(verdict) \(e.from) → \(e.to)")
            switch verdict {
            case .apply:
                fresh.append(LineFix(from: e.from, to: e.to))
                // A listed word counts as used whichever way the fix was found (a sound-alike too).
                vocabulary.used(Correction.core(e.from, e.to).to)
            case .ask where settings.askNames:
                fresh.append(LineFix(from: e.from, to: e.to, ask: true))
            default: break
            }
        }
        let fixes = Correction.merge(line.fixes ?? [], fresh)
        guard fixes != line.fixes ?? [] else { return }
        store.setFixes(in: id, lineID: line.id, fixes)
        if let now = store.session(id)?.lines.first(where: { $0.id == line.id }) { onLineFixed?(id, now) }
        onChange?()
    }

    /// 待确认 in a meeting: each (from → to) once, oldest first.
    func pending(in id: String) -> [(line: TranscriptLine, fix: LineFix)] {
        var seen: Set<String> = []
        var out: [(TranscriptLine, LineFix)] = []
        for l in store.session(id)?.lines ?? [] {
            for f in l.fixes ?? [] where f.ask == true {
                let c = Correction.core(f.from, f.to)
                if seen.insert(Self.pair(c.from, c.to)).inserted { out.append((l, f)) }
            }
        }
        return out
    }

    /// 对 / 不对 on a waiting fix: every line in the meeting waiting on the same change follows,
    /// and a yes goes into the word list so the next meeting fixes it without asking.
    func answer(_ fix: LineFix, yes: Bool, in id: String) {
        let c = Correction.core(fix.from, fix.to)
        guard let s = store.session(id) else { return }
        for l in s.lines {
            guard var fixes = l.fixes else { continue }
            var changed = false
            for k in fixes.indices where fixes[k].ask == true && Correction.core(fixes[k].from, fixes[k].to) == c {
                fixes[k].ask = nil
                if !yes { fixes[k].off = true }
                changed = true
            }
            if changed {
                store.setFixes(in: id, lineID: l.id, fixes)
                if let now = store.session(id)?.lines.first(where: { $0.id == l.id }) { onLineFixed?(id, now) }
            }
        }
        if yes { vocabulary.confirm(heard: c.from, word: c.to) } else { refused.insert(Self.pair(c.from, c.to)) }
        debugLog("fix answered \(yes ? "yes" : "no")")
        onChange?()
    }

    /// 改回: this line goes back to what was heard, and the meeting stops making this change.
    func revert(_ fix: LineFix, lineID: String, in id: String) {
        guard let l = store.session(id)?.lines.first(where: { $0.id == lineID }), var fixes = l.fixes,
              let k = fixes.firstIndex(where: { $0.from == fix.from && $0.to == fix.to }) else { return }
        fixes[k].off = true
        fixes[k].ask = nil
        store.setFixes(in: id, lineID: lineID, fixes)
        let c = Correction.core(fix.from, fix.to)
        refused.insert(Self.pair(c.from, c.to))
        refused.insert(Self.pair(fix.from, fix.to))
        let key = Self.pair(c.from, c.to)
        refusals[key, default: 0] += 1
        if refusals[key]! >= 2 { vocabulary.forget(heard: c.from, word: c.to) }
        if let now = store.session(id)?.lines.first(where: { $0.id == lineID }) { onLineFixed?(id, now) }
        debugLog("fix reverted line=\(lineID)")
        onChange?()
    }
}
