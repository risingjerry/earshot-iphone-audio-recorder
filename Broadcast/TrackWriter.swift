import AVFoundation

/// Encodes one audio stream (phone playback or microphone) to a fragmented MP4/AAC file.
/// Fragments land every 10 s, so a killed extension still leaves a playable file.
final class TrackWriter {
    let file: String
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private(set) var firstPTS: CMTime?
    private var endPTS: CMTime = .invalid

    init(dir: URL, file: String, format: CMFormatDescription) throws {
        self.file = file
        let url = dir.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        let sourceRate = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee.mSampleRate ?? 44_100
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,                  // speech: mono is enough, half the size
            AVSampleRateKey: sourceRate >= 44_100 ? sourceRate : 44_100,
            AVEncoderBitRateKey: 64_000,               // about 29 MB per hour
        ]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw NSError(domain: "Earshot", code: 1) }
        writer.add(input)
    }

    var failed: Bool { writer.status == .failed }

    var seconds: Double {
        guard let first = firstPTS, endPTS.isValid else { return 0 }
        return max(0, (endPTS - first).seconds)
    }

    func append(_ buffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        if firstPTS == nil {
            guard writer.startWriting() else { return }
            writer.startSession(atSourceTime: pts)
            firstPTS = pts
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }   // drop rather than block
        if input.append(buffer) {
            let duration = CMSampleBufferGetDuration(buffer)
            endPTS = duration.isValid ? pts + duration : pts
        }
    }

    func finish(_ done: @escaping () -> Void) {
        guard writer.status == .writing else { done(); return }
        input.markAsFinished()
        writer.finishWriting(completionHandler: done)
    }
}
