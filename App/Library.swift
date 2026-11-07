import Foundation
import SwiftUI

struct Recording: Identifiable, Equatable {
    var info: RecordingInfo
    var mac: MacInfo?
    var dir: URL
    var bytes: Int64
    var id: String { info.id }

    var isLive: Bool { info.state == .recording && !info.isStale() }
    var title: String { mac?.title ?? (info.isConversation ? "现场对话" : "手机声音") }
    func text(_ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
}

/// The recordings in the App Group container, newest first. Reloads when the extension starts or ends a
/// recording (Darwin notification) and whenever the app comes to the front.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var items: [Recording] = []

    var liveBroadcast: Recording? { items.first { $0.isLive && !$0.info.isConversation } }

    init() {
        if ProcessInfo.processInfo.arguments.contains("-EarshotDemo") { Demo.seed() }
        Store.migrateLegacy()
        MicRecorder.shared.closeOrphans()
        reload()
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let library = Unmanaged<Library>.fromOpaque(observer).takeUnretainedValue()
            Task { @MainActor in library.reload() }
        }, Store.changed as CFString, nil, .deliverImmediately)
    }

    func reload() {
        Task.detached(priority: .utility) { Export.copyPending() }
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Store.recordings, includingPropertiesForKeys: nil)) ?? []
        items = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("info.json")),
                  let info = try? Store.decoder.decode(RecordingInfo.self, from: data) else { return nil }
            let mac = (try? Data(contentsOf: dir.appendingPathComponent("mac.json")))
                .flatMap { try? Store.decoder.decode(MacInfo.self, from: $0) }
            let bytes = info.tracks.values.reduce(Int64(0)) { sum, t in
                let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(t.file).path)
                return sum + ((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
            }
            return Recording(info: info, mac: mac, dir: dir, bytes: bytes)
        }
        .sorted { $0.id > $1.id }
    }

    func delete(_ item: Recording) {
        try? FileManager.default.removeItem(at: item.dir)
        reload()
    }
}

enum Format {
    static func duration(_ s: Double) -> String {
        let t = Int(s.rounded())
        return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
                         : String(format: "%d:%02d", t / 60, t % 60)
    }

    static func minutes(_ s: Double) -> String {
        s < 60 ? "\(Int(s.rounded())) 秒" : s < 3600 ? "\(Int((s / 60).rounded())) 分钟"
            : String(format: "%.1f 小时", s / 3600)
    }

    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = Calendar.current.isDateInToday(d) ? "今天 HH:mm"
            : Calendar.current.isDateInYesterday(d) ? "昨天 HH:mm" : "M月d日 HH:mm"
        return f.string(from: d)
    }

    static func sources(_ info: RecordingInfo) -> String {
        switch (info.tracks["app"] != nil, info.tracks["mic"] != nil) {
        case (true, true): "手机声音 + 麦克风"
        case (true, false): "手机声音"
        case (false, true): "麦克风"
        case (false, false): "没有录到声音"
        }
    }
}
