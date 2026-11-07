import ActivityKit
import Foundation

/// Arms and disarms a running 待命模式 session from the app process (Action Button, Live Activity, buttons),
/// with a Live Activity while sound is being stored.
@MainActor
enum StandbyControl {
    private static var activity: Activity<RecordingActivity>?

    static func arm() {
        Standby.setArmed(true)
        activity = try? Activity.request(
            attributes: RecordingActivity(startedAt: Date(), title: "正在录手机声音", symbol: "iphone.radiowaves.left.and.right"),
            content: .init(state: .init(), staleDate: nil))
    }

    static func disarm() {
        Standby.setArmed(false)
        let current = activity
        activity = nil
        Task {
            await current?.end(nil, dismissalPolicy: .immediate)
            // Also close one left over from an earlier app process.
            for other in Activity<RecordingActivity>.activities where other.attributes.symbol != "mic.fill" {
                await other.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
