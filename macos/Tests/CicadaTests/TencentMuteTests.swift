import CoreGraphics
import Foundation
import Testing
@testable import Cicada

@MainActor
struct TencentMuteTests {
    // The window and clicks measured on the real 腾讯会议 for the Audio Hijack helper (2026-07-22).
    private let meeting = TencentMute.Window(id: 15204, frame: CGRect(x: 450, y: 191, width: 1020, height: 674))

    @Test func theMicIconCountsAndItsArrowDoesNot() {
        #expect(TencentMute.micButtonWindow(at: CGPoint(x: 697.5, y: 843.4), in: [meeting]) == meeting)
        #expect(TencentMute.micButtonWindow(at: CGPoint(x: 735, y: 843.4), in: [meeting]) == nil)
        #expect(TencentMute.micButtonWindow(at: CGPoint(x: 697.5, y: 500), in: [meeting]) == nil)
    }

    @Test func onlyTheUntitledLargeWindowIsTheMeeting() {
        func w(_ owner: String, _ name: String, _ width: CGFloat, _ height: CGFloat, layer: Int = 0, id: Int = 1) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowName as String: name, kCGWindowLayer as String: layer,
             kCGWindowNumber as String: id,
             kCGWindowBounds as String: ["X": CGFloat(10), "Y": CGFloat(20), "Width": width, "Height": height]]
        }
        let found = TencentMute.meetingWindows([
            w("TencentMeeting", "", 1020, 674, id: 7),
            w("TencentMeeting", "腾讯会议", 1020, 674, id: 8),     // the main window between meetings
            w("TencentMeeting", "", 300, 200, id: 9),            // a small panel
            w("TencentMeeting", "", 1020, 674, layer: 3, id: 10),
            w("WeChat", "", 1020, 674, id: 11),
        ])
        #expect(found == [TencentMute.Window(id: 7, frame: CGRect(x: 10, y: 20, width: 1020, height: 674))])
    }
}
