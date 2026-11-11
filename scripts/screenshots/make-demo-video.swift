// Generates the demo video used for website screenshots: a short Portuguese mini-lecture with
// keynote-style slides and synthesized narration (macOS `say`, voice Luciana).
//
//   swift scripts/screenshots/make-demo-video.swift <output.mp4>
import AVFoundation
import AppKit

struct Scene { let number: String; let title: String; let subtitle: String; let narration: String; let hue: (CGFloat, CGFloat, CGFloat) }

let scenes = [
    Scene(number: "", title: "Como planejar um podcast", subtitle: "Aula 3 · Produção de conteúdo",
          narration: "Olá, pessoal. Bem-vindos à aula de hoje sobre como planejar um podcast em cinco passos.", hue: (0.42, 0.27, 0.85)),
    Scene(number: "01", title: "Defina o público", subtitle: "Quem vai ouvir e por quê",
          narration: "Primeiro passo: defina o público. Pense em quem vai ouvir, quais problemas essas pessoas têm e por que elas escolheriam o seu programa.", hue: (0.33, 0.22, 0.78)),
    Scene(number: "02", title: "Escolha o formato", subtitle: "Entrevista, conversa ou episódio solo",
          narration: "Segundo passo: escolha o formato. Entrevistas, conversas entre apresentadores ou episódios solo. Cada formato pede um roteiro diferente.", hue: (0.20, 0.30, 0.75)),
    Scene(number: "03", title: "Planeje a temporada", subtitle: "Oito episódios antes de gravar",
          narration: "Terceiro passo: planeje uma temporada de oito episódios antes de gravar o primeiro. Isso garante consistência e evita longos intervalos entre as publicações.", hue: (0.55, 0.22, 0.72)),
    Scene(number: "04", title: "Cuide do áudio", subtitle: "Ambiente silencioso vale mais que equipamento",
          narration: "Quarto passo: cuide do áudio. Um microfone simples em um ambiente silencioso vale mais do que um equipamento caro em uma sala com eco.", hue: (0.62, 0.20, 0.58)),
    Scene(number: "05", title: "Publique com regularidade", subtitle: "Um dia fixo por pelo menos três meses",
          narration: "Quinto passo: publique com regularidade. Escolha um dia da semana e mantenha o compromisso por pelo menos três meses.", hue: (0.38, 0.24, 0.80)),
    Scene(number: "", title: "Para a próxima aula", subtitle: "Descreva o seu público ideal",
          narration: "Como tarefa, cada um deve escrever a descrição do seu público ideal até a próxima aula. Ficou decidido também que a próxima aula será sobre edição de áudio. Obrigado e até lá.", hue: (0.45, 0.25, 0.86)),
]

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let work = FileManager.default.temporaryDirectory.appendingPathComponent("audra-demo-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

func run(_ path: String, _ args: [String]) throws {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    try p.run(); p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw NSError(domain: "demo", code: Int(p.terminationStatus)) }
}

// 1. Narration per scene.
var audioFiles: [URL] = []
for (i, scene) in scenes.enumerated() {
    let url = work.appendingPathComponent("s\(i).aiff")
    try run("/usr/bin/say", ["-v", "Luciana", "-r", "175", "-o", url.path, scene.narration])
    audioFiles.append(url)
}

let width = 1920, height = 1080

func slide(_ scene: Scene, index: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
    let (r, g, b) = scene.hue
    let colors = [CGColor(srgbRed: 0.03, green: 0.025, blue: 0.05, alpha: 1), CGColor(srgbRed: r * 0.35, green: g * 0.35, blue: b * 0.42, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: CGFloat(width), y: CGFloat(height)), options: [])
    // Soft light.
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [CGColor(srgbRed: r, green: g, blue: b, alpha: 0.45), CGColor(srgbRed: r, green: g, blue: b, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 1500, y: 820), startRadius: 0, endCenter: CGPoint(x: 1500, y: 820), endRadius: 900, options: [])
    // Progress dots.
    for i in 0..<scenes.count {
        ctx.setFillColor(CGColor(gray: 1, alpha: i == index ? 0.9 : 0.22))
        ctx.fillEllipse(in: CGRect(x: 160 + i * 26, y: 150, width: 10, height: 10))
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(white: 1, alpha: alpha), .kern: tracking,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 160, y: y))
    }
    if !scene.number.isEmpty { draw(scene.number, size: 64, weight: .semibold, alpha: 0.35, y: 640) }
    draw(scene.title, size: 112, weight: .bold, alpha: 0.96, y: 480, tracking: -3)
    draw(scene.subtitle, size: 46, weight: .regular, alpha: 0.62, y: 400)
    draw("Escola de Criadores", size: 30, weight: .medium, alpha: 0.4, y: 930)
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    do {
        // 2. Concatenate narration with short pauses.
        let composition = AVMutableComposition()
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        var cursor = CMTime.zero
        var boundaries: [CMTime] = []
        let pause = CMTime(seconds: 0.8, preferredTimescale: 600)
        for url in audioFiles {
            let asset = AVURLAsset(url: url)
            let track = try await asset.loadTracks(withMediaType: .audio)[0]
            let duration = try await asset.load(.duration)
            boundaries.append(cursor)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: cursor)
            cursor = cursor + duration + pause
        }
        let total = cursor

        // 3. Slides (one frame per half second keeps the file small).
        let videoURL = work.appendingPathComponent("slides.mov")
        let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        let images = scenes.enumerated().map { slide($0.element, index: $0.offset) }
        var t = 0.0
        while t <= total.seconds {
            let index = max(0, (boundaries.lastIndex { $0.seconds <= t + 0.001 }) ?? 0)
            while !input.isReadyForMoreMediaData { usleep(1000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer!), width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer!), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            ctx.draw(images[index], in: CGRect(x: 0, y: 0, width: width, height: height))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600))
            t += 0.5
        }
        input.markAsFinished(); await writer.finishWriting()

        // 4. Mux.
        let video = AVURLAsset(url: videoURL)
        let videoSource = try await video.loadTracks(withMediaType: .video)[0]
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(total, try await video.load(.duration))), of: videoSource, at: .zero)
        try? FileManager.default.removeItem(at: output)
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
        try await export.export(to: output, as: .mp4)
        print("ok \(String(format: "%.1f", total.seconds)) s → \(output.path)")
    } catch {
        print("error: \(error)")
    }
    try? FileManager.default.removeItem(at: work)
    semaphore.signal()
}
semaphore.wait()
