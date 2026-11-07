import Foundation

/// One recording folder in the App Group container. Layout and fields: docs/CONTRACT.md.
struct RecordingInfo: Codable, Equatable {
    struct Track: Codable, Equatable {
        var file: String
        var offset: Double      // seconds from the recording start to this track's first sample
        var seconds: Double     // seconds written so far
    }
    enum State: String, Codable { case recording, finished, failed }
    /// conversation: the app records the microphone (people in the room). media: the broadcast extension
    /// records what the phone plays (video, live stream, online meeting, call). Missing in v1 files = media.
    enum Scene: String, Codable { case conversation, media }

    var version = 1
    var id: String
    var startedAt: Date
    var updatedAt: Date
    var endedAt: Date?
    var state: State
    var scene: Scene?
    var tracks: [String: Track] = [:]   // "app" (what the phone plays) and/or "mic"

    var duration: Double { tracks.values.map { $0.offset + $0.seconds }.max() ?? 0 }

    /// The extension was killed without finishing: no update for 5 minutes.
    func isStale(now: Date = Date()) -> Bool { state == .recording && now.timeIntervalSince(updatedAt) > 300 }

    var isConversation: Bool { scene == .conversation }
}

/// What the Mac writes back after transcribing (mac.json).
struct MacInfo: Codable, Equatable {
    var version = 1
    var syncedAt: Date
    var title: String
}

enum Store {
    /// From Info.plist (set by project.yml from EARSHOT_BUNDLE_PREFIX), so every build has its own group.
    static let group = Bundle.main.object(forInfoDictionaryKey: "EarshotAppGroup") as? String ?? "group.dev.earshot"
    /// Posted (Darwin notification) by the extension whenever a recording starts or ends.
    static let changed = "\(group).changed"

    static var recordings: URL {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
            ?? FileManager.default.temporaryDirectory          // only without the entitlement (previews)
        // Under Library/: the Mac's devicectl may only read and write Library/ in an App Group container.
        return root.appendingPathComponent("Library/Recordings", isDirectory: true)
    }

    /// v0.1.0 kept recordings at the container root, out of the Mac's reach; move them once.
    static func migrateLegacy() {
        let fm = FileManager.default
        guard let root = fm.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let old = root.appendingPathComponent("Recordings", isDirectory: true)
        guard let dirs = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) else { return }
        try? fm.createDirectory(at: recordings, withIntermediateDirectories: true)
        for dir in dirs { try? fm.moveItem(at: dir, to: recordings.appendingPathComponent(dir.lastPathComponent)) }
        try? fm.removeItem(at: old)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func newID(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func write(_ info: RecordingInfo, to dir: URL) {
        guard let data = try? encoder.encode(info) else { return }
        try? data.write(to: dir.appendingPathComponent("info.json"), options: .atomic)
    }

    static func load(_ dir: URL) -> RecordingInfo? {
        (try? Data(contentsOf: dir.appendingPathComponent("info.json"))).flatMap { try? decoder.decode(RecordingInfo.self, from: $0) }
    }

    static func all() -> [(dir: URL, info: RecordingInfo)] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in load(dir).map { (dir, $0) } }
    }

    /// A screen-recorder session is running right now (pressing the Action Button again should offer 停止).
    static func broadcastIsLive() -> Bool {
        all().contains { !$0.info.isConversation && $0.info.state == .recording && !$0.info.isStale() }
    }

    static func notifyChanged() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(changed as CFString), nil, nil, true)
    }
}

/// 待命模式 state shared by the app and the broadcast extension (App Group defaults).
enum Standby {
    private static let defaults = UserDefaults(suiteName: Store.group)
    /// Posted by the app after changing `armed`; the running extension starts or ends a recording.
    static let armedChanged = "\(Store.group).armed"

    /// The person turned 待命模式 on: the next screen-recorder session waits instead of recording.
    static var enabled: Bool {
        get { defaults?.bool(forKey: "standbyEnabled") ?? false }
        set { defaults?.set(newValue, forKey: "standbyEnabled") }
    }

    /// Store sound now (set by the Action Button, read by the extension).
    static var armed: Bool {
        get { defaults?.bool(forKey: "standbyArmed") ?? false }
        set { defaults?.set(newValue, forKey: "standbyArmed") }
    }

    /// Written by the extension every ~10 s while a standby session runs; nil when it ends.
    static var heartbeat: Date? {
        get { defaults?.object(forKey: "standbyHeartbeat") as? Date }
        set { defaults?.set(newValue, forKey: "standbyHeartbeat") }
    }

    /// A standby session is running right now (the extension may be killed without saying so).
    static var isRunning: Bool { heartbeat.map { Date().timeIntervalSince($0) < 30 } ?? false }

    static func setArmed(_ on: Bool) {
        armed = on
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName(armedChanged as CFString), nil, nil, true)
    }
}
