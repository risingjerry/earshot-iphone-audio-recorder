import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers

/// Lines the phone-audio and microphone files up by their offsets, for playback and for sharing as one file.
enum AudioMix {
    static func composition(_ item: Recording) async throws -> AVComposition {
        let comp = AVMutableComposition()
        for track in item.info.tracks.values {
            let asset = AVURLAsset(url: item.dir.appendingPathComponent(track.file))
            guard let source = try await asset.loadTracks(withMediaType: .audio).first,
                  let target = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let range = try await source.load(.timeRange)
            try target.insertTimeRange(range, of: source, at: CMTime(seconds: track.offset, preferredTimescale: 600))
        }
        return comp
    }

    static func export(_ item: Recording) async throws -> URL {
        let comp = try await composition(item)
        let name = "\(item.mac?.title ?? "录音") \(item.id).m4a".replacingOccurrences(of: "/", with: "-")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: out)
        guard let session = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else {
            throw NSError(domain: "Earshot", code: 3)
        }
        session.outputURL = out
        session.outputFileType = .m4a
        await session.export()
        if let error = session.error { throw error }
        return out
    }
}

/// Shared from the detail screen: the mixed file is only made when the person actually shares.
struct SharedAudio: Transferable {
    let item: Recording
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Audio) { SentTransferredFile(try await AudioMix.export($0.item)) }
    }
}
