import AVFoundation

struct ExtractedAudio: Sendable {
    /// Full speech track: 16 kHz mono PCM, the native rate of the on-device recognizer.
    let url: URL
    /// A short excerpt used for fast language identification.
    let sampleURL: URL
    let duration: Double
}

/// Decodes the first audio track of a media file into a compact 16 kHz mono file.
/// Decoding is streamed buffer by buffer, so memory stays flat regardless of the video length.
struct AudioExtractor {
    static let sampleRate: Double = 16_000
    static let languageSampleLength: Double = 40

    func extract(from source: URL, id: UUID, progress: @escaping @Sendable (Double) -> Void) async throws -> ExtractedAudio {
        let asset = AVURLAsset(url: source)
        let tracks: [AVAssetTrack]
        let duration: Double
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
            duration = try await asset.load(.duration).seconds
        } catch {
            throw MediaError.unreadable(error.localizedDescription)
        }
        guard let track = tracks.first else { throw MediaError.noAudioTrack }

        let reader: AVAssetReader
        do { reader = try AVAssetReader(asset: asset) } catch { throw MediaError.unreadable(error.localizedDescription) }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw MediaError.unreadable("Faixa de áudio incompatível.") }
        reader.add(output)

        let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false)!
        // Stored as 16-bit to halve disk usage for long recordings.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let audioURL = AppPaths.audioCache.appendingPathComponent("\(id.uuidString).caf")
        let sampleURL = AppPaths.audioCache.appendingPathComponent("\(id.uuidString)-sample.caf")
        try? FileManager.default.removeItem(at: audioURL)
        try? FileManager.default.removeItem(at: sampleURL)

        let file = try AVAudioFile(forWriting: audioURL, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let sampleFile = try AVAudioFile(forWriting: sampleURL, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)

        // Skip intros (music, vinhetas) when the video is long enough.
        let sampleStart = duration > 180 ? min(duration * 0.1, 90) : 0
        let sampleEnd = sampleStart + Self.languageSampleLength

        guard reader.startReading() else {
            throw MediaError.unreadable(reader.error?.localizedDescription ?? "Falha ao iniciar a leitura.")
        }

        var framesWritten: AVAudioFramePosition = 0
        var lastReported = -1.0

        do {
            while let sampleBuffer = output.copyNextSampleBuffer() {
                if Task.isCancelled { reader.cancelReading(); throw CancellationError() }

                let frames = CMSampleBufferGetNumSamples(sampleBuffer)
                guard frames > 0, let block = CMSampleBufferGetDataBuffer(sampleBuffer),
                      let pcm = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(frames))
                else { continue }

                let status = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: frames * MemoryLayout<Float>.size,
                                                        destination: pcm.floatChannelData![0])
                guard status == kCMBlockBufferNoErr else { continue }
                pcm.frameLength = AVAudioFrameCount(frames)

                try file.write(from: pcm)

                let time = Double(framesWritten) / Self.sampleRate
                if time >= sampleStart && time < sampleEnd { try sampleFile.write(from: pcm) }
                framesWritten += AVAudioFramePosition(frames)

                if duration > 0 {
                    let fraction = min(1, time / duration)
                    if fraction - lastReported >= 0.005 { lastReported = fraction; progress(fraction) }
                }
            }
        } catch {
            file.close(); sampleFile.close()
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: sampleURL)
            throw error
        }
        file.close()
        sampleFile.close()

        if reader.status == .failed {
            throw MediaError.unreadable(reader.error?.localizedDescription ?? "Erro de decodificação.")
        }
        guard framesWritten > 0 else { throw MediaError.emptyAudio }
        progress(1)
        return ExtractedAudio(url: audioURL, sampleURL: sampleURL, duration: Double(framesWritten) / Self.sampleRate)
    }

    static func cleanUp(id: UUID) {
        let dir = AppPaths.audioCache
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString).caf"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id.uuidString)-sample.caf"))
    }
}
