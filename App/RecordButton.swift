import SwiftUI
import ReplayKit

/// Two ways to record, side by side: the room (microphone, in the app) and the phone's own sound
/// (Apple's screen-recorder sheet with our extension preselected).
struct RecordControls: View {
    let broadcast: Recording?                 // a live screen-recorder session, if any
    @ObservedObject var mic = MicRecorder.shared
    @State private var error: String?

    var body: some View {
        HStack(spacing: 12) {
            big(title: mic.startedAt == nil ? "现场对话" : "停止",
                icon: mic.startedAt == nil ? "mic.fill" : "stop.fill",
                since: mic.startedAt, tint: mic.startedAt == nil ? .accentColor : .red,
                disabled: broadcast != nil) { toggleMic() }
            big(title: broadcast == nil ? "手机声音" : "停止",
                icon: broadcast == nil ? "iphone.radiowaves.left.and.right" : "stop.fill",
                since: broadcast?.info.startedAt, tint: broadcast == nil ? .indigo : .red,
                disabled: mic.startedAt != nil) {
                if Standby.isRunning {                            // 待命模式: store or stop right away
                    Standby.armed ? StandbyControl.disarm() : StandbyControl.arm()
                } else {
                    AppState.shared.picker.tap()
                }
            }
        }
        .background(PickerHost(picker: AppState.shared.picker).frame(width: 1, height: 1).opacity(0.01))
        .alert("录不了", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") {}
        } message: { Text(error ?? "") }
    }

    private func toggleMic() {
        if mic.isRecording { mic.stop(); return }
        Task {
            guard await MicRecorder.requestPermission() else {
                error = "没有麦克风权限：到 设置 › Earshot 打开麦克风。"
                return
            }
            do { try mic.start() } catch { self.error = error.localizedDescription }
        }
    }

    private func big(title: String, icon: String, since: Date?, tint: Color, disabled: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.headline)
                if let since {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Format.duration(ctx.date.timeIntervalSince(since))).font(.caption).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .foregroundStyle(.white)
            .background(tint, in: RoundedRectangle(cornerRadius: 16))
            .opacity(disabled ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

@MainActor
final class BroadcastPicker {
    let view: RPSystemBroadcastPickerView = {
        let v = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.preferredExtension = Bundle.main.object(forInfoDictionaryKey: "EarshotBroadcastExtension") as? String
        v.showsMicrophoneButton = true
        return v
    }()

    /// Opens Apple's sheet: 开始直播 (with a microphone switch) or, while recording, 停止直播.
    func tap() {
        view.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }
}

private struct PickerHost: UIViewRepresentable {
    let picker: BroadcastPicker
    func makeUIView(context: Context) -> UIView { picker.view }
    func updateUIView(_ view: UIView, context: Context) {}
}
