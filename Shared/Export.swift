import Foundation

/// Copies finished recordings into a folder the person picked once (an iCloud Drive folder the Mac also sees), so the Mac
/// gets them anywhere, not only on the home Wi-Fi. Audio first, info.json last: once info.json is there,
/// the folder is complete (docs/CONTRACT.md, iCloud channel).
enum Export {
    private static var bookmarkFile: URL {
        Store.recordings.deletingLastPathComponent().appendingPathComponent("export-folder.bookmark")
    }

    static func setFolder(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try FileManager.default.createDirectory(at: bookmarkFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: bookmarkFile, options: .atomic)
    }

    static func clearFolder() { try? FileManager.default.removeItem(at: bookmarkFile) }

    /// The picked folder; recordings go into its 录音 subfolder (or into it, if it is the 录音 folder).
    static func folder() -> URL? {
        guard let data = try? Data(contentsOf: bookmarkFile) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return nil }
        if stale { try? setFolder(url) }
        return url
    }

    static var folderDisplayName: String? {
        folder().map { $0.lastPathComponent == "录音" ? "\($0.deletingLastPathComponent().lastPathComponent)/录音" : "\($0.lastPathComponent)/录音" }
    }

    static func isExported(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("exported.json").path)
    }

    /// Name the Mac sees: "2026-11-07 1033 现场对话".
    static func folderName(_ info: RecordingInfo) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return "\(f.string(from: info.startedAt)) \(info.isConversation ? "现场对话" : "手机声音")"
    }

    /// Copies one finished recording. Returns true when it is (now or already) in the folder.
    @discardableResult
    static func copy(_ dir: URL, _ info: RecordingInfo) -> Bool {
        guard info.state != .recording || info.isStale(), !info.tracks.isEmpty else { return false }
        if isExported(dir) { return true }
        guard let picked = folder() else { return false }
        let scoped = picked.startAccessingSecurityScopedResource()
        defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
        let root = picked.lastPathComponent == "录音" ? picked : picked.appendingPathComponent("录音", isDirectory: true)
        let fm = FileManager.default
        var target = root.appendingPathComponent(folderName(info), isDirectory: true)
        if fm.fileExists(atPath: target.path) { target = root.appendingPathComponent("\(folderName(info)) \(info.id)") }

        var ok = true
        var failure: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: [], error: &failure) { url in
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
                for track in info.tracks.values {
                    try fm.copyItem(at: dir.appendingPathComponent(track.file), to: url.appendingPathComponent(track.file))
                }
                try fm.copyItem(at: dir.appendingPathComponent("info.json"), to: url.appendingPathComponent("info.json"))
            } catch {
                ok = false
                try? fm.removeItem(at: url)                    // never leave a half folder for the Mac
            }
        }
        guard ok, failure == nil else { return false }
        let marker = ["name": target.lastPathComponent]
        try? JSONSerialization.data(withJSONObject: marker).write(to: dir.appendingPathComponent("exported.json"))
        return true
    }

    /// Everything finished but not yet copied (the extension may not reach the folder, or none was picked then).
    static func copyPending() {
        guard folder() != nil else { return }
        for (dir, info) in Store.all() where !isExported(dir) { copy(dir, info) }
    }
}
