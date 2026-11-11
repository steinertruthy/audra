import AVFoundation
import Foundation

struct ExportSettings: Hashable {
    enum Container: String, CaseIterable, Identifiable {
        case mp4, mov, m4a
        var id: String { rawValue }
        var label: String {
            switch self {
            case .mp4: tr("MP4")
            case .mov: tr("MOV")
            case .m4a: tr("Somente áudio (M4A)")
            }
        }
        var fileType: AVFileType {
            switch self {
            case .mp4: .mp4
            case .mov: .mov
            case .m4a: .m4a
            }
        }
        var isAudioOnly: Bool { self == .m4a }
    }

    enum Codec: String, CaseIterable, Identifiable {
        case h264, hevc
        var id: String { rawValue }
        var label: String { self == .h264 ? tr("H.264 (máxima compatibilidade)") : tr("HEVC / H.265 (arquivos menores)") }
        var type: AVVideoCodecType { self == .h264 ? .h264 : .hevc }
    }

    enum Resolution: Int, CaseIterable, Identifiable {
        case project = 0, uhd = 2160, fullHD = 1080, hd = 720, sd = 480
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .project: tr("Igual ao projeto")
            case .uhd: tr("4K (2160p)")
            case .fullHD: tr("Full HD (1080p)")
            case .hd: tr("HD (720p)")
            case .sd: tr("SD (480p)")
            }
        }
    }

    enum Quality: String, CaseIterable, Identifiable {
        case high, standard, compact
        var id: String { rawValue }
        var label: String {
            switch self {
            case .high: tr("Alta")
            case .standard: tr("Padrão")
            case .compact: tr("Compacta")
            }
        }
        var bitsPerPixel: Double {
            switch self {
            case .high: 0.16
            case .standard: 0.09
            case .compact: 0.05
            }
        }
    }

    var container: Container = .mp4
    var codec: Codec = .h264
    var resolution: Resolution = .project
    var quality: Quality = .standard
    var fps: Double = 30
    var includeAudio = true

    /// Output frame size for a canvas; the short side matches the chosen resolution.
    func renderSize(for canvas: CanvasSettings) -> CGSize {
        let w = Double(canvas.width), h = Double(canvas.height)
        guard resolution != .project else { return CGSize(width: even(w), height: even(h)) }
        let scale = Double(resolution.rawValue) / min(w, h)
        return CGSize(width: even(w * scale), height: even(h * scale))
    }

    func bitrate(for size: CGSize) -> Int {
        let factor = codec == .hevc ? 0.62 : 1
        return Int(size.width * size.height * fps * quality.bitsPerPixel * factor)
    }

    func estimatedBytes(duration: Double, canvas: CanvasSettings) -> Int64 {
        let video = container.isAudioOnly ? 0 : bitrate(for: renderSize(for: canvas))
        let audio = includeAudio || container.isAudioOnly ? 192_000 : 0
        return Int64(Double(video + audio) * duration / 8)
    }

    private func even(_ v: Double) -> Double { max(2, (v / 2).rounded() * 2) }
}

/// Renders the edit to a file. Uses the same composition as the preview and the hardware encoder.
enum VideoExporter {
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set() { lock.withLock { value = true } }
    }

    static func export(_ project: EditProject, settings: ExportSettings, to destination: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        guard project.duration > 0.05 else { throw MediaError.exportFailed(tr("A timeline está vazia.")) }
        let size = settings.renderSize(for: project.canvas)
        let built = try await CompositionBuilder.build(project, renderSize: size, fps: settings.fps)
        let asset = built.asset

        let temp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).\(destination.pathExtension)")
        try? FileManager.default.removeItem(at: temp)

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: temp, fileType: settings.container.fileType)
        } catch {
            throw MediaError.exportFailed(error.localizedDescription)
        }
        reader.timeRange = CMTimeRange(start: .zero, duration: CompositionBuilder.time(built.duration))

        var videoPair: (AVAssetReaderOutput, AVAssetWriterInput)?
        if !settings.container.isAudioOnly {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: tracks, videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            output.videoComposition = built.videoComposition
            output.alwaysCopiesSampleData = false
            let fps = Int(settings.fps.rounded())
            var compression: [String: Any] = [
                AVVideoAverageBitRateKey: settings.bitrate(for: size),
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
            ]
            if settings.codec == .h264 { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: settings.codec.type,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
                AVVideoCompressionPropertiesKey: compression,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ],
            ])
            input.expectsMediaDataInRealTime = false
            guard reader.canAdd(output), writer.canAdd(input) else {
                throw MediaError.exportFailed(tr("Configuração de vídeo não suportada (%@×%@, %@).", Int(size.width), Int(size.height), settings.codec.label))
            }
            reader.add(output)
            writer.add(input)
            videoPair = (output, input)
        }

        var audioPair: (AVAssetReaderOutput, AVAssetWriterInput)?
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if (settings.includeAudio || settings.container.isAudioOnly), !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.audioMix = built.audioMix
            output.audioTimePitchAlgorithm = .spectral
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            if reader.canAdd(output), writer.canAdd(input) {
                reader.add(output)
                writer.add(input)
                audioPair = (output, input)
            }
        }
        guard videoPair != nil || audioPair != nil else {
            throw MediaError.exportFailed(settings.container.isAudioOnly ? tr("O projeto não tem áudio para exportar.") : tr("Nada para exportar."))
        }

        if settings.container == .mp4 { writer.shouldOptimizeForNetworkUse = true }
        guard reader.startReading() else {
            throw MediaError.exportFailed(reader.error?.localizedDescription ?? tr("Não foi possível ler a composição."))
        }
        guard writer.startWriting() else {
            throw MediaError.exportFailed(writer.error?.localizedDescription ?? tr("Não foi possível criar o arquivo."))
        }
        writer.startSession(atSourceTime: .zero)

        let cancelled = Flag()
        let duration = built.duration
        let trackProgress: @Sendable (CMSampleBuffer) -> Void = { sample in
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if t.isFinite { progress(min(0.995, t / duration)) }
        }

        /// AVAssetReader/Writer are not Sendable, but each is driven by exactly one queue here.
        final class Pipeline: @unchecked Sendable {
            let reader: AVAssetReader, writer: AVAssetWriter
            let video: (AVAssetReaderOutput, AVAssetWriterInput)?, audio: (AVAssetReaderOutput, AVAssetWriterInput)?
            init(_ reader: AVAssetReader, _ writer: AVAssetWriter, _ video: (AVAssetReaderOutput, AVAssetWriterInput)?,
                 _ audio: (AVAssetReaderOutput, AVAssetWriterInput)?) {
                self.reader = reader; self.writer = writer; self.video = video; self.audio = audio
            }
        }
        let pipeline = Pipeline(reader, writer, videoPair, audioPair)

        @Sendable func run() async throws {
            let reader = pipeline.reader, writer = pipeline.writer
            let video = pipeline.video, audio = pipeline.audio
            let noop: @Sendable (CMSampleBuffer) -> Void = { _ in }
            let audioProgress = video == nil ? trackProgress : noop
            _ = audio
            let videoTask = Task.detached {
                if let video = pipeline.video { await pump(video.0, into: video.1, label: "video", cancelled: cancelled, onSample: trackProgress) }
            }
            let audioTask = Task.detached {
                if let audio = pipeline.audio { await pump(audio.0, into: audio.1, label: "audio", cancelled: cancelled, onSample: audioProgress) }
            }
            await videoTask.value
            await audioTask.value
            if writer.status == .failed {
                reader.cancelReading()
                try? FileManager.default.removeItem(at: temp)
                throw MediaError.exportFailed(writer.error?.localizedDescription ?? tr("O codificador recusou um quadro."))
            }
            if cancelled.isSet || Task.isCancelled {
                reader.cancelReading()
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temp)
                throw CancellationError()
            }
            if reader.status == .failed {
                writer.cancelWriting()
                try? FileManager.default.removeItem(at: temp)
                throw MediaError.exportFailed(reader.error?.localizedDescription ?? tr("Falha ao ler a mídia de origem."))
            }
            await writer.finishWriting()
            guard writer.status == .completed else {
                try? FileManager.default.removeItem(at: temp)
                throw MediaError.exportFailed(writer.error?.localizedDescription ?? tr("Falha ao gravar o arquivo."))
            }
        }
        try await withTaskCancellationHandler(operation: run, onCancel: { cancelled.set() })

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw MediaError.exportFailed(tr("Não foi possível salvar em “%@”. %@", destination.lastPathComponent, error.localizedDescription))
        }
        progress(1)
    }

    private static func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, label: String,
                             cancelled: Flag, onSample: @escaping @Sendable (CMSampleBuffer) -> Void) async {
        let queue = DispatchQueue(label: "app.audra.export.\(label)", qos: .userInitiated)
        // Only touched from `queue`, which serializes all access.
        nonisolated(unsafe) let input = input
        nonisolated(unsafe) let output = output
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let done = Flag()
            func finish() {
                guard !done.isSet else { return }
                done.set()
                input.markAsFinished()
                continuation.resume()
            }
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData && !done.isSet {
                    if cancelled.isSet { finish(); return }
                    guard let sample = output.copyNextSampleBuffer() else { finish(); return }
                    if !input.append(sample) { cancelled.set(); finish(); return }
                    onSample(sample)
                }
            }
        }
    }
}
