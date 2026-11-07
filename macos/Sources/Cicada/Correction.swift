import Foundation

/// A word the AI service said speech recognition got wrong in a finished line ("莫拉" → "Morpho").
/// The line keeps what was heard (`src`) and carries its fixes, so a port that doesn't know them
/// still shows the heard text, and a line the record recognizer refines later keeps the fixes
/// whose words are still in it.
struct LineFix: Codable, Equatable, Hashable {
    var from: String
    var to: String
    /// Waiting for the user (a name the Mac can't check by sound): not applied until confirmed.
    var ask: Bool? = nil
    /// The user said no (改回 or 不对): kept so the same line isn't fixed that way again.
    var off: Bool? = nil

    var applied: Bool { ask != true && off != true }
}

/// Deciding which of the service's proposed fixes to take, without asking it again. Its own
/// confidence isn't enough: in a 21-minute test it rated "快销 → 区块" and "苍蝇 → 方向" above 0.85.
/// So a Chinese word may only be swapped for one that sounds alike (pinyin from the system's own
/// transform), a Latin word only for a near spelling, and a new name only once the user says so.
enum Correction {
    struct Edit: Equatable {
        var from: String
        var to: String
        var confidence: Double
    }

    enum Verdict: Equatable { case apply, ask, drop }

    static let applyAt = 0.6
    static let spellingAt = 0.8
    static let askAt = 0.8

    /// The part an edit changes, as a word: "解除质压" → "解除质押" is "质压" → "质押" (at least two
    /// characters, so one refusal doesn't block every 压 → 押), and a Latin word stays whole
    /// ("Un450P三" → "Uniswap V3", not "450P三" → "iswap V3").
    static func core(_ from: String, _ to: String) -> (from: String, to: String) {
        let a = Array(from), b = Array(to)
        var i = 0
        while i < min(a.count, b.count), a[i] == b[i] { i += 1 }
        var j = 0
        while j < min(a.count, b.count) - i, a[a.count - 1 - j] == b[b.count - 1 - j] { j += 1 }
        let word: (Character) -> Bool = { $0.isASCII && ($0.isLetter || $0.isNumber) }
        // Only a change that starts or ends inside a Latin word takes the rest of the word.
        let fromEdge = { (k: Int) -> Bool in (k < a.count && word(a[k])) || (k < b.count && word(b[k])) }
        if fromEdge(i) { while i > 0, word(a[i - 1]) { i -= 1 } }
        if (a.count - j - 1 >= 0 && word(a[a.count - j - 1])) || (b.count - j - 1 >= 0 && word(b[b.count - j - 1])) {
            while j > 0, word(a[a.count - j]) { j -= 1 }
        }
        // Two characters at least, taken from the Chinese side: "FFT制押" → "FFT质押" is "制押" → "质押".
        while a.count - j - i < 2 || b.count - j - i < 2 {
            if j > 0, !word(a[a.count - j]) { j -= 1 } else if i > 0, !word(a[i - 1]) { i -= 1 } else { break }
        }
        return (String(a[i..<(a.count - j)]), String(b[i..<(b.count - j)]))
    }

    /// `known`: the user confirmed this heard form for this word (the word list). `rejected`: they
    /// said no to it in this meeting.
    static func decide(_ e: Edit, known: (String, String) -> Bool, rejected: (String, String) -> Bool) -> Verdict {
        let c = core(e.from, e.to)
        guard !c.from.isEmpty, !c.to.isEmpty, c.from.lowercased() != c.to.lowercased(),
              !rejected(e.from, e.to), !rejected(c.from, c.to) else { return .drop }
        if known(e.from, e.to) || known(c.from, c.to) { return .apply }
        guard e.confidence >= applyAt else { return .drop }
        let latinFrom = c.from.contains(where: \.isASCIILetter), latinTo = c.to.contains(where: \.isASCIILetter)
        if !latinFrom, !latinTo, han(c.from), han(c.to), soundsAlike(c.from, c.to) { return .apply }
        if latinFrom, latinTo, c.from.allSatisfy(\.isASCII), c.to.allSatisfy(\.isASCII), e.confidence >= spellingAt,
           c.from.lowercased() != c.to.lowercased(), distance(c.from.lowercased(), c.to.lowercased()) <= 2 {
            return .apply
        }
        // A new name (Chinese heard as a Latin name, or a respelled one): sound can't check it.
        if latinTo, e.confidence >= askAt { return .ask }
        return .drop
    }

    /// Toneless pinyin, one syllable per character, from the system's Mandarin transform.
    static func pinyin(_ s: String) -> [String] {
        s.map { ch in
            let m = NSMutableString(string: String(ch))
            CFStringTransform(m, nil, kCFStringTransformMandarinLatin, false)
            CFStringTransform(m, nil, kCFStringTransformStripDiacritics, false)
            return (m as String).lowercased().trimmingCharacters(in: .whitespaces)
        }
    }

    private static let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q",
                                   "x", "r", "z", "c", "s", "y", "w"]

    private static func split(_ syllable: String) -> (String, String) {
        for i in initials where syllable.hasPrefix(i) { return (i, String(syllable.dropFirst(i.count))) }
        return ("", syllable)
    }

    /// Same number of syllables, and on average three quarters alike: a syllable counts whole when
    /// equal, half when its initial or its final matches (质/追, 销/照). 苍蝇/方向 is a quarter.
    static func soundsAlike(_ a: String, _ b: String) -> Bool {
        let x = pinyin(a), y = pinyin(b)
        guard x.count == y.count, !x.isEmpty else { return false }
        var score = 0.0
        for (p, q) in zip(x, y) {
            if p == q { score += 1; continue }
            let (i1, f1) = split(p), (i2, f2) = split(q)
            if i1 == i2 || f1 == f2 || f1.replacingOccurrences(of: "ng", with: "n") == f2.replacingOccurrences(of: "ng", with: "n") {
                score += 0.5
            }
        }
        return score / Double(x.count) >= 0.75
    }

    static func han(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var prev = row[0]
            row[0] = i + 1
            for (j, cb) in b.enumerated() {
                let cur = row[j + 1]
                row[j + 1] = min(row[j + 1] + 1, row[j] + 1, prev + (ca == cb ? 0 : 1))
                prev = cur
            }
        }
        return row[b.count]
    }

    /// The line as shown: each applied fix replaces its words where they still are. The ranges are
    /// the replaced words, for the dotted underline.
    static func apply(_ fixes: [LineFix], to src: String) -> (text: String, marks: [Range<String.Index>]) {
        var text = src
        var spans: [(String, Int)] = []   // replacement and its character offset, kept valid as text changes
        for f in fixes where f.applied && !f.from.isEmpty {
            guard let r = text.range(of: f.from) else { continue }
            let start = text.distance(from: text.startIndex, to: r.lowerBound)
            let delta = f.to.count - f.from.count
            spans = spans.map { $0.1 > start ? ($0.0, $0.1 + delta) : $0 }
            text.replaceSubrange(r, with: f.to)
            spans.append((f.to, start))
        }
        let marks = spans.compactMap { word, offset -> Range<String.Index>? in
            guard offset + word.count <= text.count else { return nil }
            let lo = text.index(text.startIndex, offsetBy: offset)
            return lo..<text.index(lo, offsetBy: word.count)
        }
        return (text, marks.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// The service's reply to a sentence sent with fixes asked for:
    /// {"translation": "…", "fixes": [{"from", "to", "confidence"}]}. nil when it isn't that shape,
    /// and the caller treats the reply as a plain translation. Fixes whose words aren't in the
    /// subtitle are dropped: the service sometimes quotes them rephrased.
    static func parse(_ reply: String, subtitle: String) -> (translation: String, edits: [Edit])? {
        // Asked for JSON in the prompt only: take the outermost {…}, fenced or not.
        guard let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
              let data = String(reply[open...close]).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translation = o["translation"] as? String else { return nil }
        let raw = o["fixes"] as? [[String: Any]] ?? []
        var edits: [Edit] = []
        for f in raw {
            guard let from = f["from"] as? String, let to = f["to"] as? String, !from.isEmpty, from != to,
                  subtitle.contains(from) else { continue }
            let c = (f["confidence"] as? Double) ?? (f["confidence"] as? NSNumber)?.doubleValue ?? 0
            edits.append(Edit(from: from, to: to, confidence: c))
        }
        return (translation.trimmingCharacters(in: .whitespacesAndNewlines), edits)
    }

    /// What the lines' fixes become after the service answered for this text again (a joined or
    /// refined line): its new fixes, plus every one the user already turned down.
    static func merge(_ old: [LineFix], _ new: [LineFix]) -> [LineFix] {
        let refused = old.filter { $0.off == true }
        let fresh = new.filter { n in !refused.contains { $0.from == n.from && $0.to == n.to } }
        return refused + fresh
    }
}

extension TranscriptLine {
    /// What the line says once its fixes are in: shown, exported and read by the notes.
    var shown: String { fixes.map { Correction.apply($0, to: src).text } ?? src }
}

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
}
