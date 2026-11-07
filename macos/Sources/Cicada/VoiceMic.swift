import AVFoundation
import AudioToolbox
import CoreAudio

/// The microphone with the system's echo cancellation (VoiceProcessingIO): with speakers on, the
/// online meeting's voices reach the mic. The talk key would translate them and speak them back, and
/// 电脑和会议室 would write each remote sentence twice. Measured with a clip on the MacBook speakers
/// at 60 %: 38–39 of 43 words recognized from the bare mic, none through this.
///
/// One unit in the process, or none: the room (listening the whole meeting) and the talk key (each
/// press) share it as consumers, and it runs while anyone is attached.
///
/// The raw unit, because AVAudioEngine's voice processing fails ('bfmt') when the default input is
/// the virtual mic, which 同声传译 makes it. Making the unit takes ~1.8 s, so it is made ahead and
/// only started (~40 ms) and stopped per press; made but stopped, it doesn't hold the mic open, but
/// it does starve AVAudioEngine's input on the same mic (−56 dB peaks): it is let go of before the
/// plain mic is used.
/// AGC is off (it lifts the room's noise with the voice, which recognition likes less), and other
/// audio's ducking is set to its minimum: the meeting must stay audible while you talk.
final class VoiceMic: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private let queue = DispatchQueue(label: "com.wquguru.cicada.voicemic")
    private let lock = NSLock()
    private var unit: AudioUnit?
    /// The devices the unit was made for: another mic or output means making it again.
    private var builtFor: (input: AudioObjectID, output: AudioObjectID)?
    private var building = false
    private var running = false
    private var consumers: [String: (AVAudioPCMBuffer) -> Void] = [:]
    private var waiting: [(Bool) -> Void] = []
    private var scratch = [Float](repeating: 0, count: 8192)
    /// After a unit is made or let go of: audio already flowing in this process goes silent for good
    /// (measured: an output engine playing into BlackHole, and the system audio tap), and must be
    /// started anew.
    var onUnitChanged: (() -> Void)?

    deinit {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
    }

    /// Whether anyone is attached (then nobody may use the plain mic, which the unit starves).
    var inUse: Bool { lock.withLock { !consumers.isEmpty } }

    /// Makes the unit for `input` and the current output in the background, unless it already is;
    /// `then` hears whether it is ready (at once when it already was).
    func prepare(input: AudioObjectID, then: ((Bool) -> Void)? = nil) {
        guard let output = SystemAudioTap.defaultOutputDevice() else { then?(false); return }
        lock.lock()
        let ready = builtFor.map { $0 == (input, output) } ?? false
        if ready { lock.unlock(); then?(true); return }
        if let then { waiting.append(then) }
        if building { lock.unlock(); return }
        building = true
        lock.unlock()
        queue.async { [self] in
            let t0 = Date()
            let made = make(input: input, output: output)
            let (ok, told) = lock.withLock { () -> (Bool, [(Bool) -> Void]) in
                if let old = unit, !running { AudioComponentInstanceDispose(old); unit = nil; builtFor = nil }
                var ok = false
                if let made, unit == nil { unit = made; builtFor = (input, output); ok = true } else if let made { AudioComponentInstanceDispose(made) }
                building = false
                defer { waiting = [] }
                return (ok, waiting)
            }
            debugLog(String(format: "voice mic: %@ in %.1f s (input %u, output %u)", ok ? "ready" : "failed",
                            Date().timeIntervalSince(t0), input, output))
            onUnitChanged?()
            told.forEach { $0(ok) }
        }
    }

    /// `key` hears `input` from now on, if the unit is ready for it and the current output (it starts
    /// with the first consumer). Otherwise false: the caller uses the plain mic this time, after
    /// `release` when nobody else is attached; a new unit is made later, not while the plain mic runs.
    func attach(_ key: String, input: AudioObjectID, onAudio: @escaping (AVAudioPCMBuffer) -> Void) -> Bool {
        guard let output = SystemAudioTap.defaultOutputDevice() else { return false }
        lock.lock()
        guard let unit, let b = builtFor, b == (input, output) else { lock.unlock(); return false }
        consumers[key] = onAudio
        let first = !running
        running = true
        lock.unlock()
        guard first else { return true }
        let status = AudioOutputUnitStart(unit)
        if status != noErr {
            debugLog("voice mic: start failed \(status)")
            lock.withLock { running = false; consumers = [:]; builtFor = nil }
            return false
        }
        debugLog("voice mic: started for \(key)")
        return true
    }

    /// `key` stops hearing; the unit stops with the last consumer.
    func detach(_ key: String) {
        lock.lock()
        guard consumers.removeValue(forKey: key) != nil else { lock.unlock(); return }
        guard consumers.isEmpty, running, let unit else { lock.unlock(); return }
        running = false
        lock.unlock()
        AudioOutputUnitStop(unit)
        debugLog("voice mic: stopped (\(key) was the last)")
    }

    /// Lets go of the unit (not while anyone is attached), so the plain mic hears again.
    func release() {
        let old: AudioUnit? = lock.withLock {
            guard !running, consumers.isEmpty, let u = unit else { return nil }
            unit = nil
            builtFor = nil
            return u
        }
        if let old {
            AudioComponentInstanceDispose(old)
            debugLog("voice mic: released")
            onUnitChanged?()
        }
    }

    private func make(input: AudioObjectID, output: AudioObjectID) -> AudioUnit? {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return nil }
        var made: AudioUnit?
        guard AudioComponentInstanceNew(comp, &made) == noErr, let u = made else { return nil }
        func set<T>(_ property: AudioUnitPropertyID, _ scope: AudioUnitScope, _ element: AudioUnitElement, _ value: T) -> Bool {
            let status = withUnsafeBytes(of: value) {
                AudioUnitSetProperty(u, property, scope, element, $0.baseAddress, UInt32($0.count))
            }
            if status != noErr { debugLog("voice mic: property \(property) failed \(status)") }
            return status == noErr
        }
        // Element 1 is the mic, element 0 the output the echo is heard against.
        var ok = set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1, input)
            && set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, output)
        _ = set(kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, UInt32(0))
        _ = set(kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0,
                AUVoiceIOOtherAudioDuckingConfiguration(mEnableAdvancedDucking: false, mDuckingLevel: .min))
        let asbd = Self.format.streamDescription.pointee
        ok = ok && set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, asbd)
            && set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, asbd)
        ok = ok && set(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                       AURenderCallbackStruct(inputProc: { ref, flags, ts, _, frames, _ in
                           Unmanaged<VoiceMic>.fromOpaque(ref).takeUnretainedValue().render(flags, ts, frames)
                       }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()))
        if ok, AudioUnitInitialize(u) == noErr { return u }
        AudioComponentInstanceDispose(u)
        return nil
    }

    /// On the real-time thread, as `SystemAudioTap.render`.
    private func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ ts: UnsafePointer<AudioTimeStamp>,
                        _ frames: UInt32) -> OSStatus {
        guard let unit, frames > 0, Int(frames) <= scratch.count else { return noErr }
        let status = scratch.withUnsafeMutableBufferPointer { p -> OSStatus in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: p.baseAddress))
            return AudioUnitRender(unit, flags, ts, 1, frames, &list)
        }
        let listeners = lock.withLock { Array(consumers.values) }
        guard status == noErr, !listeners.isEmpty, let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: frames),
              let dst = out.floatChannelData?[0] else { return status }
        out.frameLength = frames
        scratch.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: Int(frames)) }
        listeners.forEach { $0(out) }
        return noErr
    }
}

/// 会议室 heard through the echo-cancelling unit (电脑和会议室): an `AudioSource` like `RoomMic`, so the
/// rest of listening is unchanged. The unit is made on `start` (~1.8 s, the room is heard from then);
/// `onFailed` says it couldn't be, and the caller falls back to the plain mic. While `muted` (the
/// Mac reading aloud, the talk key held), silence goes on in its place, as with `RoomMic`.
final class EchoCancelledRoomMic: AudioSource, @unchecked Sendable {
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    var onFailed: (() -> Void)?
    private let mic: VoiceMic
    private let device: OutputDevice
    private let lock = NSLock()
    private var _muted = false
    private var stopped = false
    var muted: Bool {
        get { lock.withLock { _muted } }
        set { lock.withLock { _muted = newValue } }
    }
    var deviceName: String { device.name }
    var deviceUID: String { device.uid }

    init(mic: VoiceMic, device: OutputDevice) {
        self.mic = mic
        self.device = device
    }

    func start() throws {
        mic.prepare(input: device.id) { [weak self] ok in
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            let attached = ok && self.mic.attach("room", input: self.device.id) { [weak self] buf in self?.deliver(buf) }
            if !attached {
                debugLog("room mic: echo cancellation unavailable, plain mic instead")
                self.onFailed?()
            } else {
                debugLog("room mic started with echo cancellation: \(self.device.name)")
            }
        }
    }

    func stop() {
        lock.withLock { stopped = true }
        mic.detach("room")
    }

    private func deliver(_ buf: AVAudioPCMBuffer) {
        if muted, let d = buf.floatChannelData?[0] { d.update(repeating: 0, count: Int(buf.frameLength)) }
        onAudio?(buf)
    }
}
