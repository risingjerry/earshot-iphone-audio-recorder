import AppKit
import CoreGraphics
import Foundation

/// Earshot: follows 腾讯会议's microphone button, so what you say while muted there isn't recorded.
///
/// Ported from the TencentAudioHijackSync helper that drove Audio Hijack's mic gate (2026-07):
/// Tencent's accessibility tree doesn't say whether the mic is muted, so the state is followed by
/// watching real clicks on the mic icon in the meeting window's bottom toolbar. A new meeting starts
/// unmuted (Tencent's own default); the state of the current meeting window survives a relaunch.
/// Clicks only: Tencent's keyboard shortcut or the host muting you are not seen.
@MainActor
final class TencentMute {
    struct Window: Equatable {
        var id: Int
        var frame: CGRect      // global top-left coordinates, as mouse events report them
    }

    /// Called on the main queue whenever the state may have changed.
    var onChange: (() -> Void)?
    private(set) var muted = false

    private var windows: [Window] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var lastClick = Date.distantPast
    private var askedForAccess = false
    private static let stateKey = "tencentMuteState"

    /// The live meeting window has an empty title and is large; Tencent's named windows stay
    /// open between meetings.
    static func meetingWindows(_ list: [[String: Any]]) -> [Window] {
        list.compactMap { w in
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "TencentMeeting" || owner == "腾讯会议",
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowName as String] as? String ?? "").isEmpty,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width >= 800, height >= 500 else { return nil }
            return Window(id: id, frame: CGRect(x: x, y: y, width: width, height: height))
        }
    }

    /// The mic icon sits about 250 pt from the left of the bottom toolbar; the drop-down arrow just
    /// right of it must not count.
    static func micButtonWindow(at p: CGPoint, in windows: [Window]) -> Window? {
        windows.first { w in
            let x = p.x - w.frame.minX, y = p.y - w.frame.minY
            return (210...275).contains(x) && (w.frame.height - 90...w.frame.height + 5).contains(y)
        }
    }

    func start() {
        guard timer == nil else { return }
        // Once a second: is a meeting window open (cheap), and is the click watch still on.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func tick() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.meeting").isEmpty == false
        guard running else {
            if tap != nil { stopTap() }
            if !windows.isEmpty { windows = []; set(muted: false) }
            return
        }
        if tap == nil { startTap() }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            debugLog("tencent mute: click watch re-enabled")
        }
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let now = Self.meetingWindows(list)
        if windows.isEmpty, let first = now.first {
            // A meeting window appeared: the same window as before a relaunch keeps its state,
            // a new meeting starts unmuted.
            let saved = UserDefaults.standard.dictionary(forKey: Self.stateKey)
            let same = (saved?["window"] as? Int).map { id in now.contains { $0.id == id } } ?? false
            debugLog("tencent mute: meeting window \(first.id), \(same ? "state kept" : "new meeting, unmuted")")
            windows = now
            set(muted: same ? (saved?["muted"] as? Bool ?? false) : false, window: first.id)
        } else if !windows.isEmpty, now.isEmpty {
            debugLog("tencent mute: meeting window closed")
            windows = []
            set(muted: false)
        } else {
            windows = now
        }
    }

    private func set(muted: Bool, window: Int? = nil) {
        if let window { UserDefaults.standard.set(["window": window, "muted": muted], forKey: Self.stateKey) }
        guard muted != self.muted else { return }
        self.muted = muted
        onChange?()
    }

    fileprivate func clicked(at p: CGPoint) {
        guard let w = Self.micButtonWindow(at: p, in: windows), Date().timeIntervalSince(lastClick) >= 0.45 else { return }
        lastClick = Date()
        debugLog("tencent mute: mic button clicked, now \(muted ? "unmuted" : "muted")")
        set(muted: !muted, window: w.id)
    }

    private func startTap() {
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        // Listen only: clicks are never changed or held up.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let watch = Unmanaged<TencentMute>.fromOpaque(refcon).takeUnretainedValue()
            if type == .leftMouseDown {
                let p = event.location
                DispatchQueue.main.async { MainActor.assumeIsolated { watch.clicked(at: p) } }
            } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { MainActor.assumeIsolated { if let t = watch.tap { CGEvent.tapEnable(tap: t, enable: true) } } }
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else {
            // Watching clicks may need 输入监控: ask once; the next tick tries again.
            debugLog("tencent mute: no click watch, asking for Input Monitoring (preflight \(CGPreflightListenEventAccess()))")
            if !askedForAccess { askedForAccess = true; CGRequestListenEventAccess() }
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        debugLog("tencent mute: 腾讯会议 is running, watching its mic button")
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        debugLog("tencent mute: 腾讯会议 quit, click watch off")
    }

    /// Debug (`tencentTap`): open the click watch now, as if 腾讯会议 were running, to see it is allowed.
    func probeTap() {
        if tap == nil { startTap() }
        debugLog("tencent mute: click watch \(tap != nil ? "on" : "off"), input monitoring \(CGPreflightListenEventAccess())")
    }

    /// Debug (`tencentMute:<on|off>`): as if the mic button was clicked into that state.
    func simulate(muted: Bool) { set(muted: muted) }
}
