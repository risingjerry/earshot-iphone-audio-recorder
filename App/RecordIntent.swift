import AppIntents
import AVFoundation

/// What the app should do once it is in front (set by the Action Button intent).
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    enum Pending { case picker, mic }
    @Published var pending: Pending?
    let picker = BroadcastPicker()
}

/// The Action Button. One press picks the scene by itself:
/// - 待命模式 session running → start / stop storing the phone's sound right away, no sheet;
/// - recording already → stop (a screen-recorder session is stopped from Apple's sheet, opened for you);
/// - another app is playing sound (video, live stream, meeting, call) → record that sound: the app opens
///   Apple's screen-recorder sheet, one tap on 开始直播 (Apple requires that tap);
/// - silence → record the microphone (a conversation) at once, in the background, with a Live Activity.
struct RecordIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Earshot 录音"
    static let description = IntentDescription("手机在放声音就录这个 App 的声音，没在放就录现场对话；录音中再按一次就停止。")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @MainActor
    func perform() async throws -> some IntentResult {
        let mic = MicRecorder.shared
        if mic.isRecording {
            mic.stop()
            return .result()
        }
        if Standby.isRunning {                           // 待命模式: no sheet, no tap
            if Standby.armed { StandbyControl.disarm(); return .result() }
            if AVAudioSession.sharedInstance().isOtherAudioPlaying { StandbyControl.arm(); return .result() }
        }
        if Store.broadcastIsLive() || AVAudioSession.sharedInstance().isOtherAudioPlaying {
            AppState.shared.pending = .picker
            try await continueInForeground(nil, alwaysConfirm: false)
            return .result()
        }
        guard MicRecorder.hasPermission else {           // first time: the permission prompt needs the app in front
            AppState.shared.pending = .mic
            try await continueInForeground(nil, alwaysConfirm: false)
            return .result()
        }
        try mic.start()
        return .result()
    }
}

struct EarshotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordIntent(), phrases: ["用 \(.applicationName) 录音"],
                    shortTitle: "录音", systemImageName: "waveform")
    }
}
