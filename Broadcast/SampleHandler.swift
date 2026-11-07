import ReplayKit
import AVFoundation

/// The system screen recorder hands us video, phone-playback audio and (if the person turned it on) microphone audio.
/// Video frames are dropped untouched; each audio stream goes to its own file. Contract: docs/CONTRACT.md.
///
/// Standby mode (待命模式): the session runs all day but stores nothing until the Action Button arms it;
/// each arm → disarm becomes one recording. Apple's sheet is needed only once, to start the session.
final class SampleHandler: RPBroadcastSampleHandler {
    private let queue = DispatchQueue(label: "earshot.recorder")
    private var standby = false
    private var dir: URL?
    private var info: RecordingInfo?
    private var writers: [String: TrackWriter] = [:]
    private var startPTS: CMTime?
    private var lastSave = Date.distantPast
    private var lastBeat = Date.distantPast

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        queue.sync {
            standby = Standby.enabled
            if standby {
                Standby.armed = false
                Standby.heartbeat = Date()
                let me = Unmanaged.passUnretained(self).toOpaque()
                CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), me, { _, me, _, _, _ in
                    guard let me else { return }
                    let handler = Unmanaged<SampleHandler>.fromOpaque(me).takeUnretainedValue()
                    handler.queue.async { handler.applyArmed() }
                }, Standby.armedChanged as CFString, nil, .deliverImmediately)
            } else {
                begin()
            }
        }
        Store.notifyChanged()
    }

    override func processSampleBuffer(_ buffer: CMSampleBuffer, with type: RPSampleBufferType) {
        if standby, Date().timeIntervalSince(lastBeat) >= 10 {   // "the standby session is alive"
            lastBeat = Date()
            Standby.heartbeat = lastBeat
        }
        let key: String
        switch type {
        case .audioApp: key = "app"
        case .audioMic: key = "mic"
        default: return                                        // video: never touched
        }
        guard CMSampleBufferDataIsReady(buffer) else { return }
        queue.sync { append(buffer, key: key) }
    }

    // MARK: one recording

    private func applyArmed() {
        if Standby.armed, dir == nil { begin(); Store.notifyChanged() }
        if !Standby.armed, dir != nil { end(); Store.notifyChanged() }
    }

    private func begin() {
        let now = Date()
        let id = Store.newID(now)
        let dir = Store.recordings.appendingPathComponent(id, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            if !standby {
                finishBroadcastWithError(NSError(domain: "Earshot", code: 2,
                                                 userInfo: [NSLocalizedDescriptionKey: "无法创建录音文件夹"]))
            }
            return
        }
        self.dir = dir
        let info = RecordingInfo(id: id, startedAt: now, updatedAt: now, state: .recording, scene: .media)
        self.info = info
        writers = [:]
        startPTS = nil
        lastSave = now
        Store.write(info, to: dir)
    }

    private func end() {
        let group = DispatchGroup()
        for w in writers.values {
            group.enter()
            w.finish { group.leave() }
        }
        _ = group.wait(timeout: .now() + 5)                   // the system kills the extension shortly after
        save(state: .finished)
        // Straight into the picked iCloud folder if the extension may reach it; otherwise the app
        // copies it the next time it comes to the front.
        if let dir, let info { Export.copy(dir, info) }
        writers = [:]
        dir = nil
        info = nil
        startPTS = nil
    }

    private func append(_ buffer: CMSampleBuffer, key: String) {
        guard let dir, info != nil else { return }             // standby and not armed: nothing is stored
        if writers[key] == nil {
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let w = try? TrackWriter(dir: dir, file: "\(key).m4a", format: format) else { return }
            writers[key] = w
        }
        guard let w = writers[key] else { return }
        w.append(buffer)
        if startPTS == nil { startPTS = w.firstPTS }
        if Date().timeIntervalSince(lastSave) >= 10 { save(state: .recording) }
    }

    private func save(state: RecordingInfo.State) {
        guard let dir, var info else { return }
        let now = Date()
        info.updatedAt = now
        info.state = state
        if state != .recording { info.endedAt = now }
        for (key, w) in writers {
            guard let first = w.firstPTS, !w.failed else { continue }
            let offset = startPTS.map { max(0, (first - $0).seconds) } ?? 0
            info.tracks[key] = .init(file: w.file, offset: offset, seconds: w.seconds)
        }
        self.info = info
        lastSave = now
        Store.write(info, to: dir)
    }

    override func broadcastFinished() {
        queue.sync {
            if dir != nil { end() }
            if standby {
                Standby.armed = false
                Standby.heartbeat = nil
                CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                        Unmanaged.passUnretained(self).toOpaque())
            }
        }
        Store.notifyChanged()
    }
}
