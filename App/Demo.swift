import Foundation

/// `-EarshotDemo` launch argument: replaces the list with made-up recordings, for screenshots.
enum Demo {
    static func seed() {
        let fm = FileManager.default
        try? fm.removeItem(at: Store.recordings)
        let now = Date()
        let items: [(minutesAgo: Double, seconds: Double, scene: RecordingInfo.Scene, mic: Bool, title: String?, summary: String?)] = [
            (12, 1_920, .media, true, "产品周会：下周上线范围", """
            # 产品周会：下周上线范围

            ## 一句话总结
            确定下周只上线搜索改版，导出功能推迟一周。

            ## 达成的约定
            - 搜索改版周三冻结代码，周五上线。
            - 导出功能等设计稿定稿后再排期。

            ## 待办
            - 小林：周二前补齐搜索的埋点。
            - 阿杰：周三前给出导出的设计稿。
            """),
            (95, 640, .conversation, false, "和房东聊续租", nil),
            (1_500, 2_700, .media, false, "直播：独立开发者怎么定价", nil),
            (2_950, 75, .conversation, false, nil, nil),
        ]
        for item in items {
            let start = now.addingTimeInterval(-item.minutesAgo * 60)
            let id = Store.newID(start)
            let dir = Store.recordings.appendingPathComponent(id, isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var tracks: [String: RecordingInfo.Track] = [:]
            if item.scene == .conversation {
                tracks["mic"] = .init(file: "mic.caf", offset: 0, seconds: item.seconds)
            } else {
                tracks["app"] = .init(file: "app.m4a", offset: 0, seconds: item.seconds)
                if item.mic { tracks["mic"] = .init(file: "mic.m4a", offset: 0.4, seconds: item.seconds) }
            }
            let info = RecordingInfo(id: id, startedAt: start, updatedAt: start.addingTimeInterval(item.seconds),
                                     endedAt: start.addingTimeInterval(item.seconds), state: .finished,
                                     scene: item.scene, tracks: tracks)
            Store.write(info, to: dir)
            if let title = item.title, let data = try? Store.encoder.encode(MacInfo(syncedAt: now, title: title)) {
                try? data.write(to: dir.appendingPathComponent("mac.json"))
            }
            if let summary = item.summary {
                try? summary.write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
            }
        }
    }
}
