import SwiftUI

@main
struct EarshotApp: App {
    @StateObject private var library = Library()
    @ObservedObject private var state = AppState.shared
    @Environment(\.scenePhase) private var phase

    init() {
        RecordingControl.stop = {
            if MicRecorder.shared.isRecording { MicRecorder.shared.stop() } else if Standby.armed { StandbyControl.disarm() }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .onChange(of: phase) { _, now in
                    if now == .active { library.reload(); runPending() }
                }
                .onChange(of: state.pending) { _, _ in runPending() }
        }
    }

    /// The Action Button asked for something that needs the app in front.
    private func runPending() {
        guard phase == .active, let pending = state.pending else { return }
        state.pending = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))   // let the window settle before presenting a sheet
            switch pending {
            case .picker:
                state.picker.tap()
            case .mic:
                if await MicRecorder.requestPermission() { try? MicRecorder.shared.start() }
            }
        }
    }
}
