import AVFoundation
import Foundation

/// The AVFoundation objects that play or export an `EditProject`.
struct BuiltComposition: @unchecked Sendable {
    let asset: AVComposition
    let videoComposition: AVVideoComposition
    let audioMix: AVAudioMix?
    let duration: Double
    let renderSize: CGSize
}

/// Translates the editing model into an AVComposition + video composition + audio mix.
/// The preview player and the exporter both call this, so they can never disagree.
enum CompositionBuilder {
    static let timescale: CMTimeScale = 60_000

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: max(0, seconds), preferredTimescale: timescale)
    }

    private struct AudioSegment {
        var start: Double
        var end: Double
        var volume: Double
        var fadeIn: Double
        var fadeOut: Double
    }

    /// Per-clip timing after resolving transitions with the neighbouring clip.
    private struct Placement {
        var clip: EditClip
        var media: MediaItem
        var headExtension = 0.0
        var tailExtension = 0.0
        var effects: [LayerEffect] = []
        var audioFadeIn = 0.0
    }

    static func build(_ project: EditProject, pool: MediaPool = .shared,
                      renderSize: CGSize? = nil, fps: Double? = nil) async throws -> BuiltComposition {
        let total = max(project.duration, 1.0 / max(1, project.canvas.fps))
        let totalTime = time(total)
        let composition = AVMutableComposition()

        // Base layer: keeps the compositor fed for the whole duration.
        let baseAsset = AVURLAsset(url: try await BlackVideo.ensure())
        guard let baseSource = try await baseAsset.loadTracks(withMediaType: .video).first,
              let baseTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MediaError.exportFailed("Não foi possível preparar a composição.")
        }
        let baseDuration = try await baseAsset.load(.duration)
        try baseTrack.insertTimeRange(CMTimeRange(start: .zero, duration: baseDuration), of: baseSource, at: .zero)
        baseTrack.scaleTimeRange(CMTimeRange(start: .zero, duration: baseDuration), toDuration: totalTime)

        var layers: [VideoLayer] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []

        // Video tracks, bottom to top (the first video track in the list is drawn on top).
        let videoTracks = project.tracks.filter { $0.kind == .video }.reversed()
        for track in videoTracks {
            let placements = try await resolve(track: track, in: project, pool: pool)
            var videoPair: [AVMutableCompositionTrack] = []
            var audioPair: [AVMutableCompositionTrack] = []
            var audioSegments: [[AudioSegment]] = [[], []]

            for (index, placement) in placements.enumerated() {
                let slot = index % 2
                let loaded = try await pool.load(placement.media)
                let clip = placement.clip
                let compStart = clip.start - placement.headExtension
                let compEnd = clip.end + placement.tailExtension
                let srcStart = clip.sourceIn - placement.headExtension * clip.speed
                let srcEnd = clip.sourceOut + placement.tailExtension * clip.speed

                if !track.isHidden, let source = loaded.video {
                    while videoPair.count <= slot {
                        guard let t = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { break }
                        videoPair.append(t)
                    }
                    if slot < videoPair.count {
                        try insert(source, from: srcStart, to: srcEnd, at: compStart, duration: compEnd - compStart, into: videoPair[slot])
                        layers.append(VideoLayer(trackID: videoPair[slot].trackID, start: compStart, end: compEnd,
                                                 clipStart: clip.start, clipEnd: clip.end,
                                                 orientation: loaded.orientation, transform: clip.transform, crop: clip.crop,
                                                 opacity: clip.opacity, fadeIn: clip.fadeIn, fadeOut: clip.fadeOut,
                                                 effects: placement.effects))
                    }
                }

                let audible = !track.isMuted && !clip.audioMuted && clip.volume > 0.001
                if audible, let source = loaded.audio {
                    while audioPair.count <= slot {
                        guard let t = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { break }
                        audioPair.append(t)
                    }
                    if slot < audioPair.count {
                        try insert(source, from: srcStart, to: srcEnd, at: compStart, duration: compEnd - compStart, into: audioPair[slot])
                        audioSegments[slot].append(AudioSegment(start: compStart, end: compEnd, volume: clip.volume,
                                                                fadeIn: max(clip.audioFadeIn, placement.audioFadeIn),
                                                                fadeOut: max(clip.audioFadeOut, placement.tailExtension)))
                    }
                }
            }
            for (slot, track) in audioPair.enumerated() {
                audioParameters.append(parameters(for: track, segments: audioSegments[slot]))
            }
        }

        // Audio tracks.
        for track in project.tracks where track.kind == .audio && !track.isMuted {
            var compTrack: AVMutableCompositionTrack?
            var segments: [AudioSegment] = []
            for clip in track.clips.sorted(by: { $0.start < $1.start }) where !clip.audioMuted && clip.volume > 0.001 {
                guard let media = project.mediaItem(clip.mediaID), media.isAvailable,
                      let source = try await pool.load(media).audio else { continue }
                if compTrack == nil {
                    compTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                guard let compTrack else { break }
                try insert(source, from: clip.sourceIn, to: clip.sourceOut, at: clip.start, duration: clip.duration, into: compTrack)
                segments.append(AudioSegment(start: clip.start, end: clip.end, volume: clip.volume,
                                             fadeIn: clip.audioFadeIn, fadeOut: clip.audioFadeOut))
            }
            if let compTrack { audioParameters.append(parameters(for: compTrack, segments: segments)) }
        }

        // Text, topmost track last so it draws on top.
        var texts: [TextLayer] = []
        for track in project.tracks.reversed() where track.kind == .text && !track.isHidden {
            for clip in track.clips {
                guard let style = clip.text, !style.content.isEmpty else { continue }
                texts.append(TextLayer(start: clip.start, end: clip.end, style: style))
            }
        }

        let instructions = makeInstructions(layers: layers, texts: texts, total: total,
                                            compositionEnd: max(composition.duration, totalTime),
                                            background: project.canvas.background, baseTrackID: baseTrack.trackID)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = AudraCompositor.self
        let size = renderSize ?? project.canvas.size
        videoComposition.renderSize = CGSize(width: max(2, (size.width / 2).rounded() * 2), height: max(2, (size.height / 2).rounded() * 2))
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, (fps ?? project.canvas.fps).rounded())))
        videoComposition.instructions = instructions
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2

        var mix: AVMutableAudioMix?
        if !audioParameters.isEmpty {
            mix = AVMutableAudioMix()
            mix?.inputParameters = audioParameters
        }

        return BuiltComposition(asset: composition.copy() as! AVComposition, videoComposition: videoComposition,
                                audioMix: mix, duration: total, renderSize: videoComposition.renderSize)
    }

    // MARK: - Transitions

    private static func resolve(track: EditTrack, in project: EditProject, pool: MediaPool) async throws -> [Placement] {
        var placements: [Placement] = []
        for clip in track.clips.sorted(by: { $0.start < $1.start }) {
            guard let media = project.mediaItem(clip.mediaID), media.isAvailable, clip.duration > 0.001 else { continue }
            placements.append(Placement(clip: clip, media: media))
        }

        for i in placements.indices {
            let clip = placements[i].clip
            guard let transition = clip.transition, transition.duration > 0.01 else { continue }
            let previous = i > 0 ? placements[i - 1] : nil
            let adjacent = previous.map { abs($0.clip.end - clip.start) < 0.02 } ?? false
            let d = min(transition.duration, clip.duration / 2, adjacent ? previous!.clip.duration / 2 : .infinity)
            guard d > 0.01 else { continue }

            switch transition.kind {
            case .dipToBlack, .dipToWhite:
                let white = transition.kind == .dipToWhite
                placements[i].effects.append(LayerEffect(kind: .dip(white: white, entering: true), start: clip.start, end: clip.start + d / 2))
                if adjacent {
                    let prev = placements[i - 1].clip
                    placements[i - 1].effects.append(LayerEffect(kind: .dip(white: white, entering: false), start: prev.end - d / 2, end: prev.end))
                }
            case .dissolve, .slideLeft, .wipeLeft:
                let kind: LayerEffect.Kind = transition.kind == .dissolve ? .dissolve : transition.kind == .slideLeft ? .slideLeft : .wipeLeft
                guard adjacent, let previous else {
                    // No outgoing clip: the transition reveals the clip over whatever is below it.
                    placements[i].effects.append(LayerEffect(kind: kind, start: clip.start, end: clip.start + d))
                    placements[i].audioFadeIn = d
                    continue
                }
                let tailAvailable = (previous.media.duration - previous.clip.sourceOut) / previous.clip.speed
                let headAvailable = clip.sourceIn / clip.speed
                if tailAvailable >= d - 1e-3 {
                    // Outgoing clip keeps playing under the incoming one.
                    placements[i - 1].tailExtension = d
                    placements[i].effects.append(LayerEffect(kind: kind, start: clip.start, end: clip.start + d))
                    placements[i].audioFadeIn = d
                } else if headAvailable >= d - 1e-3 {
                    // Incoming clip starts early, over the end of the outgoing one.
                    placements[i].headExtension = d
                    placements[i].effects.append(LayerEffect(kind: kind, start: clip.start - d, end: clip.start))
                    placements[i].audioFadeIn = d
                } else {
                    // No spare media on either side: fall back to a dip through black.
                    placements[i].effects.append(LayerEffect(kind: .dip(white: false, entering: true), start: clip.start, end: clip.start + d / 2))
                    placements[i - 1].effects.append(LayerEffect(kind: .dip(white: false, entering: false), start: previous.clip.end - d / 2, end: previous.clip.end))
                }
            }
        }
        return placements
    }

    // MARK: - Helpers

    private static func insert(_ source: AVAssetTrack, from srcStart: Double, to srcEnd: Double, at start: Double,
                               duration: Double, into track: AVMutableCompositionTrack) throws {
        let sourceRange = CMTimeRange(start: time(srcStart), end: time(srcEnd))
        let at = time(start)
        let trackEnd = track.timeRange.end
        if at > trackEnd, trackEnd.isValid {
            track.insertEmptyTimeRange(CMTimeRange(start: trackEnd, end: at))
        }
        try track.insertTimeRange(sourceRange, of: source, at: at)
        let target = time(duration)
        if abs(target.seconds - sourceRange.duration.seconds) > 1e-4 {
            track.scaleTimeRange(CMTimeRange(start: at, duration: sourceRange.duration), toDuration: target)
        }
    }

    private static func parameters(for track: AVMutableCompositionTrack, segments: [AudioSegment]) -> AVMutableAudioMixInputParameters {
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTimePitchAlgorithm = .spectral
        params.setVolume(0, at: .zero)
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            let length = segment.end - segment.start
            let fadeIn = min(segment.fadeIn, length / 2), fadeOut = min(segment.fadeOut, length / 2)
            let volume = Float(segment.volume)
            if fadeIn > 0.005 {
                params.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume,
                                     timeRange: CMTimeRange(start: time(segment.start), end: time(segment.start + fadeIn)))
            } else {
                params.setVolume(volume, at: time(segment.start))
            }
            if fadeOut > 0.005 {
                params.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                                     timeRange: CMTimeRange(start: time(segment.end - fadeOut), end: time(segment.end)))
            }
        }
        return params
    }

    private static func makeInstructions(layers: [VideoLayer], texts: [TextLayer], total: Double, compositionEnd: CMTime,
                                         background: RGBAColor, baseTrackID: CMPersistentTrackID) -> [AudraInstruction] {
        var cuts: Set<CMTimeValue> = [0, time(total).value]
        for layer in layers {
            cuts.insert(time(min(total, layer.start)).value)
            cuts.insert(time(min(total, layer.end)).value)
        }
        for text in texts {
            cuts.insert(time(min(total, text.start)).value)
            cuts.insert(time(min(total, text.end)).value)
        }
        let points = cuts.sorted()
        var instructions: [AudraInstruction] = []
        for (index, (a, b)) in zip(points, points.dropFirst()).enumerated() where b > a {
            let start = CMTime(value: a, timescale: timescale)
            var end = CMTime(value: b, timescale: timescale)
            if index == points.count - 2, compositionEnd > end { end = compositionEnd }
            let lo = start.seconds, hi = end.seconds
            let active = layers.filter { $0.start < hi - 1e-6 && $0.end > lo + 1e-6 }
            let activeTexts = texts.filter { $0.start < hi - 1e-6 && $0.end > lo + 1e-6 }
            instructions.append(AudraInstruction(timeRange: CMTimeRange(start: start, end: end), layers: active,
                                                 texts: activeTexts, background: background, baseTrackID: baseTrackID))
        }
        return instructions
    }
}
