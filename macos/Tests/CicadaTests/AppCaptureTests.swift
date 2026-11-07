import Foundation
import Testing
@testable import Cicada

struct AppCaptureTests {
    private func proc(_ bundle: String, _ path: String = "") -> AppCapture.Process {
        AppCapture.Process(object: 1, pid: 1, bundleID: bundle, path: path)
    }

    @Test func helpersBelongToTheirApp() {
        #expect(AppCapture.belongs(proc("com.electron.lark.helper"), targets: ["com.electron.lark"], bundlePaths: []))
        #expect(AppCapture.belongs(proc("com.tencent.meeting"), targets: ["com.tencent.meeting"], bundlePaths: []))
    }

    @Test func aSimilarIdIsAnotherApp() {
        #expect(!AppCapture.belongs(proc("com.tencent.xinWeChat2"), targets: ["com.tencent.xinWeChat"], bundlePaths: []))
        #expect(AppCapture.belongs(proc("com.tencent.xinWeChat2"), targets: ["com.tencent.xinWeChat2"], bundlePaths: []))
    }

    @Test func aHelperWithoutIdBelongsByWhereItLives() {
        let helper = proc("", "/Applications/TencentMeeting.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper")
        #expect(AppCapture.belongs(helper, targets: ["com.tencent.meeting"], bundlePaths: ["/Applications/TencentMeeting.app/"]))
        let other = proc("", "/Applications/TencentMeetingX.app/Contents/MacOS/X")
        #expect(!AppCapture.belongs(other, targets: ["com.tencent.meeting"], bundlePaths: ["/Applications/TencentMeeting.app/"]))
    }

    @Test func anExecutablePathIsATarget() {
        #expect(AppCapture.belongs(proc("", "/usr/bin/afplay"), targets: ["/usr/bin/afplay"], bundlePaths: []))
        #expect(!AppCapture.belongs(proc("com.google.Chrome"), targets: ["/usr/bin/afplay"], bundlePaths: []))
    }
}
