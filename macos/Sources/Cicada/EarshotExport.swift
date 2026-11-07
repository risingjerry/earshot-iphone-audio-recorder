import AVFoundation
import Foundation

/// Earshot: hands a finished Mac recording to the same transcribe-and-summarise pipeline as the
/// iPhone's (`mac/earshot.py`, docs/CONTRACT.md "第二条通道"): a folder in the configured
/// `icloud_dir` with app.m4a (what the Mac played), mic.m4a (your microphone) and, written last,
/// info.json. earshot.py picks it up on its next sync. No `icloud_dir` configured: nothing is exported.
enum EarshotExport {
    struct Track: Equatable {
        var name: String      // "app" or "mic"
        var source: URL
        var seconds: Double
    }

    /// `icloud_dir` from ~/.config/earshot/config.json (or $EARSHOT_CONFIG), as earshot.py reads it.
    static func destination(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let dir = environment["EARSHOT_ICLOUD_DIR"], !dir.isEmpty { return URL(fileURLWithPath: expand(dir)) }
        let path = expand(environment["EARSHOT_CONFIG"] ?? "~/.config/earshot/config.json")
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dir = json["icloud_dir"] as? String, !dir.isEmpty else { return nil }
        return URL(fileURLWithPath: expand(dir))
    }

    private static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    /// The contract's id: the UTC start time, "20261107T073903Z".
    static func recordingID(_ date: Date) -> String {
        stamp(date, "yyyyMMdd'T'HHmmss'Z'", TimeZone(identifier: "UTC")!)
    }

    /// The folder name the phone uses, in Beijing time: "2026-11-07 1539 电脑声音".
    static func folderName(_ date: Date) -> String {
        stamp(date, "yyyy-MM-dd HHmm", TimeZone(identifier: "Asia/Shanghai")!) + " 电脑声音"
    }

    private static func stamp(_ date: Date, _ format: String, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = format
        return f.string(from: date)
    }

    /// info.json as earshot.py expects it (version 1; scene "mac" = what the Mac played plus your mic).
    static func info(id: String, startedAt: Date, endedAt: Date, tracks: [Track]) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var out: [String: Any] = [:]
        for t in tracks {
            // A decimal, so the JSON says 7.4 rather than 7.4000000000000004.
            out[t.name] = ["file": "\(t.name).m4a", "offset": 0, "seconds": NSDecimalNumber(string: String(format: "%.1f", t.seconds))]
        }
        return [
            "version": 1, "id": id, "state": "finished", "scene": "mac",
            "startedAt": iso.string(from: startedAt), "updatedAt": iso.string(from: endedAt),
            "endedAt": iso.string(from: endedAt), "tracks": out,
        ]
    }

    static func seconds(_ url: URL) -> Double? {
        guard let f = try? AVAudioFile(forReading: url), f.fileFormat.sampleRate > 0 else { return nil }
        return Double(f.length) / f.fileFormat.sampleRate
    }

    /// Exports once: a marker in the meeting's own folder stops a second copy. Runs off the main thread.
    static func export(session: Session, folder: URL, system: URL, room: URL, talk: URL) {
        guard session.sourceFile == nil, session.hasAudio, let root = destination() else { return }
        let marker = folder.appendingPathComponent("earshot-export.json")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: marker.path) else { return }
        var tracks: [Track] = []
        if let s = seconds(system), s > 0 { tracks.append(Track(name: "app", source: system, seconds: s)) }
        // Your microphone on the meeting's timeline; without it, the talk key's clips.
        if let s = seconds(room), s > 0 {
            tracks.append(Track(name: "mic", source: room, seconds: s))
        } else if let s = seconds(talk), s > 0 {
            tracks.append(Track(name: "mic", source: talk, seconds: s))
        }
        guard !tracks.isEmpty else { return }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            var dir = root.appendingPathComponent(folderName(session.startedAt), isDirectory: true)
            var n = 2
            while fm.fileExists(atPath: dir.path) {
                dir = root.appendingPathComponent(folderName(session.startedAt) + " \(n)", isDirectory: true)
                n += 1
            }
            try fm.createDirectory(at: dir, withIntermediateDirectories: false)
            for t in tracks { try fm.copyItem(at: t.source, to: dir.appendingPathComponent("\(t.name).m4a")) }
            let id = recordingID(session.startedAt)
            let end = session.endedAt ?? session.startedAt.addingTimeInterval(tracks.map(\.seconds).max() ?? 0)
            let json = try JSONSerialization.data(withJSONObject: info(id: id, startedAt: session.startedAt,
                                                                        endedAt: end, tracks: tracks),
                                                  options: [.prettyPrinted, .sortedKeys])
            // Last: earshot.py treats a folder with info.json as complete.
            try json.write(to: dir.appendingPathComponent("info.json"), options: .atomic)
            try JSONSerialization.data(withJSONObject: ["id": id, "folder": dir.path]).write(to: marker, options: .atomic)
            debugLog("earshot export: \(session.id) → \(dir.lastPathComponent) (\(tracks.map(\.name).joined(separator: "+")))")
        } catch {
            debugLog("earshot export failed for \(session.id): \(error.localizedDescription)")
        }
    }
}
