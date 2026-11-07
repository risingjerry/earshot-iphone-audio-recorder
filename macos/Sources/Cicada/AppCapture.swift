import AppKit
import CoreAudio
import Darwin
import Foundation

/// Earshot: hear only chosen apps (what Audio Hijack's per-app sources did), not everything the Mac plays.
///
/// An app often plays through helpers (`com.electron.lark.helper`, WebKit/GPU processes inside the
/// bundle, some with no bundle id at all), so a process belongs to a target when its bundle id is the
/// target or starts with "<target>.", or when its executable lives inside the target's app bundle.
/// `com.tencent.xinWeChat` therefore does not take in `com.tencent.xinWeChat2`.
enum AppCapture {
    /// The apps Audio Hijack recorded on this Mac before Earshot replaced it.
    static let defaultApps = [
        "com.tencent.meeting", "com.tencent.xinWeChat", "com.tencent.xinWeChat2",
        "com.electron.lark", "com.bytedance.douyin.desktop", "com.apple.QuickTimePlayerX",
    ]

    /// The name shown in Settings: the app's own, else a known one.
    static func name(_ id: String) -> String {
        let known = ["com.tencent.meeting": "腾讯会议", "com.tencent.xinWeChat": "微信", "com.tencent.xinWeChat2": "微信 2",
                     "com.electron.lark": "飞书", "com.bytedance.douyin.desktop": "抖音",
                     "com.apple.QuickTimePlayerX": "QuickTime Player"]
        if let k = known[id] { return k }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
    }

    struct Process: Equatable {
        var object: AudioObjectID
        var pid: pid_t
        var bundleID: String
        var path: String
    }

    /// Pure: does this process play for one of the targets? `bundlePaths` are the targets' app
    /// folders ("/Applications/Lark.app/"), each ending in "/". A target may also be an absolute
    /// executable path (a command-line player, for testing).
    static func belongs(_ p: Process, targets: [String], bundlePaths: [String]) -> Bool {
        for t in targets where !t.isEmpty {
            if t.hasPrefix("/") {
                if p.path == t { return true }
            } else if p.bundleID == t || p.bundleID.hasPrefix(t + ".") {
                return true
            }
        }
        return bundlePaths.contains { !$0.isEmpty && p.path.hasPrefix($0) }
    }

    static func bundlePaths(_ targets: [String]) -> [String] {
        targets.filter { !$0.hasPrefix("/") }.compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { $0.path + "/" }
        }
    }

    /// Every process Core Audio knows (macOS 14.2+), with its bundle id and executable path.
    static func processes() -> [Process] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            let pid = pidOf(id)
            return Process(object: id, pid: pid, bundleID: bundleIDOf(id) ?? "", path: pid > 0 ? pathOf(pid) : "")
        }
    }

    /// The process objects to tap for `targets`, in a stable order so a change can be noticed.
    static func objects(for targets: [String]) -> [AudioObjectID] {
        let paths = bundlePaths(targets)
        return processes().filter { belongs($0, targets: targets, bundlePaths: paths) }.map(\.object).sorted()
    }

    /// A chosen app that doesn't hold calls (抖音, QuickTime…) is playing sound right now: like Audio
    /// Hijack, that starts a recording. Meeting and chat apps start one by their calls instead
    /// (`MicUsers.currentCalls`), or every message chime would.
    static func mediaPlaying(_ targets: [String]) -> Bool {
        let media = targets.filter { !MicUsers.meetingApps.contains($0) && !MicUsers.callApps.contains($0) }
        guard !media.isEmpty else { return false }
        let paths = bundlePaths(media)
        return processes().contains { belongs($0, targets: media, bundlePaths: paths) && isPlaying($0.object) }
    }

    /// The app (any of its processes) is reading a microphone and playing at the same time.
    static func inCall(_ target: String) -> Bool {
        let paths = bundlePaths([target])
        let own = processes().filter { belongs($0, targets: [target], bundlePaths: paths) }
        return own.contains { isPlaying($0.object) } && own.contains { isReading($0.object) }
    }

    private static func isReading(_ id: AudioObjectID) -> Bool {
        flag(id, kAudioProcessPropertyIsRunningInput)
    }

    private static func isPlaying(_ id: AudioObjectID) -> Bool {
        flag(id, kAudioProcessPropertyIsRunningOutput)
    }

    private static func flag(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    private static func pidOf(_ id: AudioObjectID) -> pid_t {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &pid) == noErr ? pid : -1
    }

    private static func bundleIDOf(_ id: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func pathOf(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return n > 0 ? String(cString: buffer) : ""
    }

    /// Calls `onChange` (on the main queue) whenever Core Audio's process list changes: a target app
    /// launched, quit, or started a helper that plays its calls. Keep the returned token; `stop` it.
    final class Watch {
        private var block: AudioObjectPropertyListenerBlock?
        private static var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                                mScope: kAudioObjectPropertyScopeGlobal,
                                                                mElement: kAudioObjectPropertyElementMain)

        init(_ onChange: @escaping () -> Void) {
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.address, .main, block) == noErr {
                self.block = block
            }
        }

        func stop() {
            if let block {
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.address, .main, block)
            }
            block = nil
        }

        deinit { stop() }
    }
}
