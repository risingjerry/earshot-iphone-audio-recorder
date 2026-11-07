import AVFoundation
import ActivityKit

/// Records the microphone (a conversation in the room) inside the app, also when started from the Action Button
/// with the app in the background. AAC in a CAF file: readable even if the app is killed mid-recording.
@MainActor
final class MicRecorder: ObservableObject {
    static let shared = MicRecorder()

    @Published private(set) var startedAt: Date?
    private var recorder: AVAudioRecorder?
    private var dir: URL?
    private var info: RecordingInfo?
    private var timer: Timer?
    private var activity: Activity<RecordingActivity>?

    var isRecording: Bool { recorder != nil }

    private init() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                               queue: .main) { note in
            // A phone call pauses the recorder; carry on when it ends.
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw == AVAudioSession.InterruptionType.ended.rawValue else { return }
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setActive(true)
                MicRecorder.shared.recorder?.record()
            }
        }
    }

    static var hasPermission: Bool { AVAudioApplication.shared.recordPermission == .granted }

    static func requestPermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    func start() throws {
        guard recorder == nil else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let now = Date()
        let id = Store.newID(now)
        let dir = Store.recordings.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let rec = try AVAudioRecorder(url: dir.appendingPathComponent("mic.caf"), settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ])
        guard rec.record() else { throw NSError(domain: "Earshot", code: 4, userInfo: [NSLocalizedDescriptionKey: "麦克风没能开始录音"]) }

        recorder = rec
        self.dir = dir
        startedAt = now
        info = RecordingInfo(id: id, startedAt: now, updatedAt: now, state: .recording, scene: .conversation,
                             tracks: ["mic": .init(file: "mic.caf", offset: 0, seconds: 0)])
        save()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor in MicRecorder.shared.save() }
        }
        activity = try? Activity.request(attributes: RecordingActivity(startedAt: now),
                                         content: .init(state: .init(), staleDate: nil))
        Store.notifyChanged()
    }

    func stop() {
        guard let recorder else { return }
        save()                                     // currentTime is 0 once stopped
        recorder.stop()
        self.recorder = nil
        timer?.invalidate()
        timer = nil
        startedAt = nil
        if var info, let dir {
            info.state = .finished
            info.endedAt = Date()
            info.updatedAt = Date()
            Store.write(info, to: dir)
            Task.detached { Export.copy(dir, info) }
        }
        info = nil
        dir = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let activity = self.activity
        self.activity = nil
        Task { await activity?.end(nil, dismissalPolicy: .immediate) }
        Store.notifyChanged()
    }

    private func save() {
        guard let recorder, var info, let dir else { return }
        info.updatedAt = Date()
        info.tracks["mic"]?.seconds = recorder.currentTime
        self.info = info
        Store.write(info, to: dir)
    }

    /// A conversation left "recording" by a killed app: close it so it can be played and sent to the Mac.
    func closeOrphans() {
        for (dir, var info) in Store.all() where info.isConversation && info.state == .recording && dir != self.dir {
            if let seconds = try? AVAudioPlayer(contentsOf: dir.appendingPathComponent("mic.caf")).duration {
                info.tracks["mic"]?.seconds = seconds
            }
            info.state = .finished
            info.endedAt = info.updatedAt
            Store.write(info, to: dir)
        }
    }
}
