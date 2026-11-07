import Foundation
import Testing
@testable import Cicada

struct EarshotExportTests {
    private let start = ISO8601DateFormatter().date(from: "2026-11-07T07:39:03Z")!

    @Test func idIsTheUTCStartAndFolderIsBeijingTime() {
        #expect(EarshotExport.recordingID(start) == "20261107T073903Z")
        #expect(EarshotExport.folderName(start) == "2026-11-07 1539 电脑声音")
    }

    @Test func infoFollowsTheContract() {
        let tracks = [EarshotExport.Track(name: "app", source: URL(fileURLWithPath: "/a"), seconds: 12.34),
                      EarshotExport.Track(name: "mic", source: URL(fileURLWithPath: "/b"), seconds: 12.0)]
        let info = EarshotExport.info(id: "20261107T073903Z", startedAt: start, endedAt: start.addingTimeInterval(13), tracks: tracks)
        #expect(info["version"] as? Int == 1)
        #expect(info["state"] as? String == "finished")
        #expect(info["scene"] as? String == "mac")
        #expect(info["endedAt"] as? String == "2026-11-07T07:39:16Z")
        let t = info["tracks"] as? [String: [String: Any]]
        #expect(t?["app"]?["file"] as? String == "app.m4a")
        #expect(t?["mic"]?["file"] as? String == "mic.m4a")
        #expect((t?["app"]?["seconds"] as? NSNumber)?.doubleValue == 12.3)
        #expect((t?["mic"]?["offset"] as? NSNumber)?.intValue == 0)
    }

    @Test func destinationComesFromTheEarshotConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = dir.appendingPathComponent("config.json")
        try #"{"icloud_dir": "/tmp/录音"}"#.write(to: config, atomically: true, encoding: .utf8)
        #expect(EarshotExport.destination(environment: ["EARSHOT_CONFIG": config.path])?.path == "/tmp/录音")
        #expect(EarshotExport.destination(environment: ["EARSHOT_CONFIG": dir.appendingPathComponent("none").path]) == nil)
        #expect(EarshotExport.destination(environment: ["EARSHOT_ICLOUD_DIR": "/x"])?.path == "/x")
    }
}
