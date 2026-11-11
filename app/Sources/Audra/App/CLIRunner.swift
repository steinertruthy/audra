import AVFoundation
import AppKit

/// Headless mode for diagnostics and automation:
///   Audra --transcribe <arquivo> [--language pt-BR] [--summary] [--srt]
/// Runs the same media → language → transcription → summary pipeline as the app and prints the result.
enum CLIRunner {
    static func runIfRequested() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-demo"), index + 2 < args.count {
            runBlocking { try await renderDemo(input: URL(fileURLWithPath: args[index + 1]), out: URL(fileURLWithPath: args[index + 2])) }
        }
        guard let index = args.firstIndex(of: "--transcribe"), index + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[index + 1])
        let language = args.firstIndex(of: "--language").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let wantsSummary = args.contains("--summary")
        let wantsSRT = args.contains("--srt")

        let done = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0
        Task.detached {
            do {
                try await run(url: url, language: language, summary: wantsSummary, srt: wantsSRT)
            } catch {
                FileHandle.standardError.write(Data("erro: \(error.localizedDescription)\n".utf8))
                exitCode = 1
            }
            done.signal()
        }
        done.wait()
        exit(exitCode)
    }

    private static func runBlocking(_ work: @escaping @Sendable () async throws -> Void) -> Never {
        let done = DispatchSemaphore(value: 0)
        var code: Int32 = 0
        Task.detached {
            do { try await work() } catch {
                FileHandle.standardError.write(Data("erro: \(error.localizedDescription)\n".utf8))
                code = 1
            }
            done.signal()
        }
        done.wait()
        exit(code)
    }

    /// Builds a small edit (cuts, ripple delete, transition, speed, transform, text, fades), exports it
    /// and writes poster frames, to verify the engine without the UI.
    private static func renderDemo(input: URL, out: URL) async throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let item = try await MediaPool.probe(url: input)
        log("mídia: \(item.duration)s \(item.width)x\(item.height) fps=\(item.frameRate)")
        var project = EditProject(name: "Demo")
        project.canvas.width = item.width
        project.canvas.height = item.height
        project.media.append(item)
        guard let clip = project.insert(media: item, at: 0) else { throw MediaError.exportFailed("insert") }
        project.split(at: 10, clipIDs: [clip.id])
        project.split(at: 20)
        project.rippleDelete(from: 10, to: 20)            // timeline: src 0-10, then src 20-end at t=10
        let second = project.tracks.flatMap(\.clips).first { abs($0.start - 10) < 0.01 }!
        if let loc = project.location(of: second.id) {
            project.tracks[loc.track].clips[loc.clip].transition = ClipTransition(kind: .dissolve, duration: 1)
            project.tracks[loc.track].clips[loc.clip].transform = ClipTransform(scale: 0.8, x: 0.05, y: 0, rotation: 4)
        }
        project.split(at: 30)
        let third = project.tracks.flatMap(\.clips).first { abs($0.start - 30) < 0.01 }!
        project.setSpeed(third.id, 2)
        if let loc = project.location(of: third.id) {
            project.tracks[loc.track].clips[loc.clip].fadeOut = 1.5
            project.tracks[loc.track].clips[loc.clip].audioFadeOut = 1.5
        }
        project.insertText(.title("Audra — Demo"), at: 0, duration: 4)
        var lower = TextStyle.lowerThird("Reunião semanal\nEditado no Audra")
        lower.animationIn = .typewriter
        project.insertText(lower, at: 4, duration: 5)
        let expected = project.duration
        log("duração esperada: \(String(format: "%.3f", expected))s; clipes: \(project.tracks.map { "\($0.name)=\($0.clips.count)" })")

        let url = out.appendingPathComponent("demo.mp4")
        let clock = ContinuousClock(), start = clock.now
        var settings = ExportSettings()
        settings.resolution = .hd
        settings.fps = 30
        try await VideoExporter.export(project, settings: settings, to: url) { _ in }
        log("exportado em \(clock.now - start)")

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let size = try await video.first?.load(.naturalSize) ?? .zero
        log("saída: \(String(format: "%.3f", duration))s, vídeo=\(video.count) \(size), áudio=\(audio.count)")

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for t in [1.0, 6.0, 9.5, 10.5, 12.0, 25.0, expected - 0.6] {
            let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(String(format: "frame-%05.1f.png", t)))
        }
        var audioOnly = ExportSettings()
        audioOnly.container = .m4a
        try await VideoExporter.export(project, settings: audioOnly, to: out.appendingPathComponent("demo.m4a")) { _ in }
        let m4a = try await AVURLAsset(url: out.appendingPathComponent("demo.m4a")).load(.duration).seconds
        log("m4a: \(String(format: "%.3f", m4a))s")
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private static func run(url: URL, language: String?, summary: Bool, srt: Bool) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let id = UUID()
        defer { AudioExtractor.cleanUp(id: id) }

        var media = url
        if MediaInspector.needsProxy.contains(url.pathExtension.lowercased()) {
            let proxy = AppPaths.audioCache.appendingPathComponent("\(id.uuidString).mp4")
            try await FFmpegBridge.makePlayableProxy(from: url, to: proxy)
            media = proxy
        }
        let info = try await MediaInspector.inspect(media)
        log("mídia: \(TimeFormat.clock(info.duration)), vídeo=\(info.hasVideo), áudio=\(info.hasAudio)")

        let audio = try await AudioExtractor().extract(from: media, id: id) { _ in }
        log("áudio extraído em \(clock.now - start)")

        let locale: Locale
        if let language, let resolved = await SpeechEngine.resolve(language) {
            locale = resolved
        } else {
            locale = try await LanguageDetector.detect(sampleURL: audio.sampleURL) { log($0) }
        }
        log("idioma: \(locale.identifier(.bcp47)) (\(clock.now - start))")
        try await SpeechEngine.ensureAssets(for: locale)

        let segments = try await SpeechEngine.transcribe(audioURL: audio.url, locale: locale, duration: audio.duration) { _, _ in }
        let elapsed = clock.now - start
        log("transcrição: \(segments.count) trechos em \(elapsed) (\(String(format: "%.1f", audio.duration / Double(elapsed.components.seconds + 1)))× tempo real)")

        print(srt ? TranscriptRenderer.srt(segments: segments)
                  : TranscriptRenderer.plainText(title: url.lastPathComponent, segments: segments))

        if summary {
            let request = SummaryRequest(title: url.deletingPathExtension().lastPathComponent, segments: segments,
                                         localeIdentifier: locale.identifier(.bcp47), detail: Preferences.summaryDetail)
            let result = try await SummarizerFactory.make().summarize(request) { _ in }
            print(TranscriptRenderer.summaryMarkdown(title: request.title, meta: TimeFormat.clock(info.duration), summary: result))
            log("resumo concluído em \(clock.now - start)")
        }
    }
}
