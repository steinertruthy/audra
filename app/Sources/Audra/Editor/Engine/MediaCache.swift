import AVFoundation
import AppKit
import Observation

/// Evenly spaced poster frames for a media file, used to paint video clips on the timeline.
struct ThumbnailStrip: @unchecked Sendable {
    let interval: Double
    let images: [CGImage?]

    func image(at sourceTime: Double) -> CGImage? {
        guard !images.isEmpty, interval > 0 else { return nil }
        let index = min(images.count - 1, max(0, Int((sourceTime / interval).rounded(.down))))
        if let image = images[index] { return image }
        // Fall back to the nearest frame that has loaded.
        for offset in 1..<images.count {
            if index - offset >= 0, let image = images[index - offset] { return image }
            if index + offset < images.count, let image = images[index + offset] { return image }
        }
        return nil
    }
}

/// Peak levels (0…1) at a fixed rate, used to draw waveforms and to align cuts with silence.
struct Waveform: Sendable {
    static let rate = 100.0
    let peaks: [Float]

    func peak(from a: Double, to b: Double) -> Float {
        let lo = max(0, Int(a * Self.rate)), hi = min(peaks.count, max(lo + 1, Int(b * Self.rate)))
        guard lo < hi else { return 0 }
        var m: Float = 0
        for i in lo..<hi where peaks[i] > m { m = peaks[i] }
        return m
    }

    /// Quietest moment inside `range` (media time), so cuts land between words rather than inside them.
    func quietestPoint(in range: ClosedRange<Double>, fallback: Double) -> Double {
        let lo = max(0, Int(range.lowerBound * Self.rate)), hi = min(peaks.count - 1, Int(range.upperBound * Self.rate))
        guard lo < hi else { return fallback }
        var best = Int(fallback * Self.rate), bestValue = Float.greatestFiniteMagnitude
        for i in lo...hi {
            // Average a few bins so a single quiet sample does not win.
            let a = max(0, i - 2), b = min(peaks.count - 1, i + 2)
            var sum: Float = 0
            for j in a...b { sum += peaks[j] }
            let distancePenalty = Float(abs(Double(i) / Self.rate - fallback)) * 0.03
            let value = sum / Float(b - a + 1) + distancePenalty
            if value < bestValue { bestValue = value; best = i }
        }
        return Double(best) / Self.rate
    }
}

/// Loads thumbnails and waveforms in the background and keeps them in memory and on disk.
@MainActor
@Observable
final class MediaCache {
    static let shared = MediaCache()

    private(set) var thumbnails: [UUID: ThumbnailStrip] = [:]
    private(set) var waveforms: [UUID: Waveform] = [:]
    @ObservationIgnored private var pending: Set<String> = []

    func thumbnails(for item: MediaItem) -> ThumbnailStrip? {
        if let strip = thumbnails[item.id] { return strip }
        requestThumbnails(item)
        return nil
    }

    func waveform(for item: MediaItem) -> Waveform? {
        if let wave = waveforms[item.id] { return wave }
        requestWaveform(item)
        return nil
    }

    /// Poster frame for library cards.
    func poster(for item: MediaItem) -> CGImage? {
        thumbnails(for: item)?.image(at: min(1, item.duration / 3))
    }

    private func requestThumbnails(_ item: MediaItem) {
        guard item.hasVideo, item.isAvailable, pending.insert("t\(item.id)").inserted else { return }
        let url = item.playableURL
        let duration = item.duration
        let id = item.id
        Task.detached(priority: .utility) {
            let interval = max(0.5, duration / 360)
            let count = max(1, Int((duration / interval).rounded(.up)))
            var images = [CGImage?](repeating: nil, count: count)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 192, height: 108)
            let tolerance = CMTime(seconds: interval / 2, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            let times = (0..<count).map { CMTime(seconds: Double($0) * interval + min(0.1, interval / 2), preferredTimescale: 600) }

            var delivered = 0
            for await result in generator.images(for: times) {
                if case .success(let requested, let image, _) = result {
                    let index = Int((requested.seconds / interval).rounded(.down))
                    if index >= 0, index < count { images[index] = image }
                }
                delivered += 1
                // Publish progressively so the timeline fills in as frames arrive.
                if delivered == 8 || delivered % 40 == 0 || delivered == count {
                    let snapshot = ThumbnailStrip(interval: interval, images: images)
                    await MainActor.run { MediaCache.shared.thumbnails[id] = snapshot }
                }
            }
            let final = ThumbnailStrip(interval: interval, images: images)
            await MainActor.run { MediaCache.shared.thumbnails[id] = final }
        }
    }

    private func requestWaveform(_ item: MediaItem) {
        guard item.hasAudio, item.isAvailable, pending.insert("w\(item.id)").inserted else { return }
        let url = item.playableURL
        let id = item.id
        let cacheFile = AppPaths.editorCache.appendingPathComponent("wave-\(Self.cacheKey(item)).bin")
        Task.detached(priority: .utility) {
            if let data = try? Data(contentsOf: cacheFile), !data.isEmpty {
                let peaks = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                await MainActor.run { MediaCache.shared.waveforms[id] = Waveform(peaks: peaks) }
                return
            }
            guard let peaks = try? await Self.computePeaks(url: url) else { return }
            try? peaks.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: cacheFile, options: .atomic)
            await MainActor.run { MediaCache.shared.waveforms[id] = Waveform(peaks: peaks) }
        }
    }

    nonisolated static func cacheKey(_ item: MediaItem) -> String {
        let values = try? item.playableURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let raw = "\(item.playableURL.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        var hash: UInt64 = 1469598103934665603
        for byte in raw.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }

    /// Streams the audio at 8 kHz mono and keeps the peak of every 10 ms window.
    nonisolated static func computePeaks(url: URL) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let sampleRate = 8000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        reader.startReading()
        let window = Int(sampleRate / Waveform.rate)
        var peaks: [Float] = []
        var current: Float = 0, count = 0
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var floats = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let byteCount = floats.count * MemoryLayout<Float>.size
            let status = floats.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount,
                                           destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            for sample in floats {
                let v = abs(sample)
                if v > current { current = v }
                count += 1
                if count == window { peaks.append(min(1, current)); current = 0; count = 0 }
            }
        }
        if count > 0 { peaks.append(min(1, current)) }
        // Normalize gently so quiet recordings still show a readable shape.
        if let maximum = peaks.max(), maximum > 0.01, maximum < 0.9 {
            let gain = min(4, 0.9 / maximum)
            peaks = peaks.map { min(1, $0 * gain) }
        }
        return peaks
    }
}
