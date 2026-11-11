import Foundation

/// A caption in media time.
struct CaptionCue: Hashable {
    var text: String
    var start: Double
    var end: Double
}

/// Groups timed words into short, readable captions (at most two lines).
enum CaptionBuilder {
    static func cues(from segments: [TranscriptSegment], maxCharacters: Int = 84, maxDuration: Double = 5.5,
                     lineLength: Int = 42) -> [CaptionCue] {
        var cues: [CaptionCue] = []
        for segment in segments {
            var words: [TranscriptWord] = []
            func flush() {
                guard let first = words.first, let last = words.last else { return }
                let text = wrap(words.map(\.text).joined(separator: " "), lineLength: lineLength)
                cues.append(CaptionCue(text: text, start: first.start, end: max(last.end, first.start + 0.4)))
                words = []
            }
            for word in segment.timedWords {
                let candidate = (words.map(\.text) + [word.text]).joined(separator: " ")
                if let first = words.first,
                   candidate.count > maxCharacters || word.end - first.start > maxDuration {
                    flush()
                }
                words.append(word)
                let endsSentence = word.text.last.map { ".?!…".contains($0) } ?? false
                if endsSentence, let first = words.first, word.end - first.start > 1.2 { flush() }
            }
            flush()
        }
        // Avoid overlaps between consecutive cues.
        for i in cues.indices.dropLast() where cues[i].end > cues[i + 1].start {
            cues[i].end = cues[i + 1].start
        }
        return cues
    }

    /// Balanced two-line wrap.
    static func wrap(_ text: String, lineLength: Int) -> String {
        guard text.count > lineLength else { return text }
        let words = text.split(separator: " ").map(String.init)
        var best = text, bestScore = Int.max
        for i in 1..<words.count {
            let a = words[..<i].joined(separator: " "), b = words[i...].joined(separator: " ")
            let score = abs(a.count - b.count) + (max(a.count, b.count) > lineLength ? 100 : 0)
            if score < bestScore { bestScore = score; best = a + "\n" + b }
        }
        return best
    }
}

extension EditProject {
    /// Replaces the generated subtitle track with captions mapped onto the current edit.
    @discardableResult
    mutating func generateSubtitles(from segments: [TranscriptSegment], media mediaID: UUID) -> Int {
        // Keep only words that are still in the edit; a removed run splits the sentence so captions
        // never show words that were cut.
        var kept: [TranscriptSegment] = []
        for segment in segments {
            var run: [TranscriptWord] = []
            func flush() {
                guard let first = run.first, let last = run.last else { return }
                kept.append(TranscriptSegment(start: first.start, end: last.end,
                                              text: run.map(\.text).joined(separator: " "), words: run))
                run = []
            }
            for word in segment.timedWords {
                if coverage(source: word.start, word.end, media: mediaID) >= 0.5 { run.append(word) } else { flush() }
            }
            flush()
        }
        let cues = CaptionBuilder.cues(from: kept)
        var clips: [EditClip] = []
        for cue in cues {
            for range in timelineRanges(forSource: cue.start, cue.end, media: mediaID) where range.upperBound - range.lowerBound >= 0.25 {
                clips.append(.text(.caption(cue.text), start: range.lowerBound, duration: range.upperBound - range.lowerBound))
            }
        }
        clips.sort { $0.start < $1.start }
        for i in clips.indices.dropLast() where clips[i].end > clips[i + 1].start {
            clips[i].sourceOut = max(Self.minimumClipDuration, clips[i + 1].start - clips[i].start)
        }

        if let index = tracks.firstIndex(where: { $0.role == .subtitles }) {
            tracks[index].clips = clips
        } else {
            var track = EditTrack(kind: .text, name: tr("Legendas"), role: .subtitles)
            track.clips = clips
            tracks.insert(track, at: 0)
        }
        return clips.count
    }

    /// Removes media range `[a, b)` of `mediaID` from the edit, closing gaps on all unlocked tracks.
    /// Returns the timeline ranges removed.
    @discardableResult
    mutating func removeSource(_ a: Double, _ b: Double, media mediaID: UUID) -> [ClosedRange<Double>] {
        let ranges = timelineRanges(forSource: a, b, media: mediaID)
        rippleDelete(ranges: ranges)
        return ranges
    }

    /// Silences media range `[a, b)` of `mediaID` wherever it plays, without changing timing.
    mutating func muteSource(_ a: Double, _ b: Double, media mediaID: UUID) {
        let ranges = timelineRanges(forSource: a, b, media: mediaID)
        for range in ranges {
            let ids = Set(tracks.flatMap(\.clips).filter { $0.mediaID == mediaID && $0.end > range.lowerBound && $0.start < range.upperBound }.map(\.id))
            split(at: range.lowerBound, clipIDs: ids)
            let ids2 = Set(tracks.flatMap(\.clips).filter { $0.mediaID == mediaID && $0.end > range.lowerBound && $0.start < range.upperBound }.map(\.id))
            split(at: range.upperBound, clipIDs: ids2)
            for t in tracks.indices where !tracks[t].isLocked {
                for c in tracks[t].clips.indices {
                    let clip = tracks[t].clips[c]
                    if clip.mediaID == mediaID, clip.start >= range.lowerBound - 1e-3, clip.end <= range.upperBound + 1e-3 {
                        tracks[t].clips[c].audioMuted = true
                    }
                }
            }
        }
    }
}
