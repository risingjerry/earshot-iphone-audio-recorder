import ActivityKit
import AppIntents

/// Live Activity (lock screen + Dynamic Island) while a recording started from the Action Button runs.
struct RecordingActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {}
    var startedAt: Date
    var title: String = "正在录现场对话"
    var symbol: String = "mic.fill"
}

/// The stop button on the Live Activity. Runs in the app's process, which is recording.
struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "停止录音"

    @MainActor
    func perform() async throws -> some IntentResult {
        RecordingControl.stop?()
        return .result()
    }
}

/// Set by the app at launch; the widget extension never calls it.
@MainActor
enum RecordingControl {
    static var stop: (() -> Void)?
}
