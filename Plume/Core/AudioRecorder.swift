import AVFoundation

enum RecorderError: LocalizedError {
    case noInput
    case converter

    var errorDescription: String? {
        switch self {
        case .noInput: return "Aucun micro disponible."
        case .converter: return "Format audio du micro non pris en charge."
        }
    }
}

/// Enregistre le micro et le convertit à la volée en 16 kHz mono (format attendu par Whisper).
final class AudioRecorder {
    /// Niveau sonore (RMS) de chaque bloc reçu, pour animer la vague.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInput }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { throw RecorderError.converter }
        self.converter = converter

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Arrête l'enregistrement et renvoie les échantillons 16 kHz.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        lock.lock()
        defer { lock.unlock() }
        let result = samples
        samples.removeAll()
        return result
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.floatChannelData?[0] else { return }

        let count = Int(output.frameLength)
        guard count > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))

        var sum: Float = 0
        for value in chunk { sum += value * value }
        let rms = (sum / Float(count)).squareRoot()

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
        onLevel?(rms)
    }
}
