import Foundation

/// Pure editing operations on `EditProject`. Every operation keeps the invariant that clips on the
/// same track never overlap, and never touches locked tracks.
extension EditProject {
    static let minimumClipDuration = 1.0 / 30

    // MARK: Lookup

    var duration: Double {
        tracks.flatMap(\.clips).map(\.end).max() ?? 0
    }

    func mediaItem(_ id: UUID?) -> MediaItem? {
        guard let id else { return nil }
        return media.first { $0.id == id }
    }

    func location(of clipID: UUID) -> (track: Int, clip: Int)? {
        for (t, track) in tracks.enumerated() {
            if let c = track.clips.firstIndex(where: { $0.id == clipID }) { return (t, c) }
        }
        return nil
    }

    func clip(_ id: UUID) -> EditClip? {
        location(of: id).map { tracks[$0.track].clips[$0.clip] }
    }

    func track(containing clipID: UUID) -> EditTrack? {
        location(of: clipID).map { tracks[$0.track] }
    }

    /// Tracks in timeline display order (titles, video, audio).
    var displayTracks: [EditTrack] {
        tracks.enumerated()
            .sorted { ($0.element.kind.displayRank, $0.offset) < ($1.element.kind.displayRank, $1.offset) }
            .map(\.element)
    }

    func trackIndex(_ id: UUID) -> Int? { tracks.firstIndex { $0.id == id } }

    /// Longest the clip may become given its media (text clips are unbounded).
    func maxSourceOut(for clip: EditClip) -> Double {
        guard let media = mediaItem(clip.mediaID) else { return .infinity }
        return media.duration
    }

    // MARK: Placement

    /// Whether `[start, start+duration)` is free on the track, ignoring the clips in `excluding`.
    func isFree(track index: Int, start: Double, duration: Double, excluding: Set<UUID> = []) -> Bool {
        guard start >= -1e-6 else { return false }
        let end = start + duration
        return !tracks[index].clips.contains { clip in
            !excluding.contains(clip.id) && clip.start < end - 1e-6 && clip.end > start + 1e-6
        }
    }

    /// Closest start to `proposed` where the clip fits on the track.
    func nearestFreeStart(track index: Int, proposed: Double, duration: Double, excluding: Set<UUID> = []) -> Double? {
        let proposed = max(0, proposed)
        if isFree(track: index, start: proposed, duration: duration, excluding: excluding) { return proposed }
        var candidates: [Double] = [0]
        for clip in tracks[index].clips where !excluding.contains(clip.id) {
            candidates.append(clip.end)
            candidates.append(clip.start - duration)
        }
        return candidates
            .filter { $0 >= 0 && isFree(track: index, start: $0, duration: duration, excluding: excluding) }
            .min { abs($0 - proposed) < abs($1 - proposed) }
    }

    /// End of the last clip on a track.
    func trackEnd(_ index: Int) -> Double { tracks[index].clips.map(\.end).max() ?? 0 }

    mutating func sortClips(track index: Int) {
        tracks[index].clips.sort { $0.start < $1.start }
    }

    // MARK: Insert

    /// Places a clip of `media` on a compatible track at `time` (or the end of the track when nil).
    @discardableResult
    mutating func insert(media item: MediaItem, at time: Double?, trackID: UUID? = nil) -> EditClip? {
        let wantedKind: TrackKind = item.hasVideo ? .video : .audio
        var index = trackID.flatMap(trackIndex)
        if let i = index, tracks[i].kind != wantedKind || tracks[i].isLocked { index = nil }
        if index == nil {
            index = tracks.firstIndex { $0.kind == wantedKind && !$0.isLocked }
        }
        if index == nil {
            addTrack(wantedKind)
            index = tracks.lastIndex { $0.kind == wantedKind }
        }
        guard let index else { return nil }
        let start = time ?? trackEnd(index)
        guard let placed = nearestFreeStart(track: index, proposed: start, duration: item.duration) else { return nil }
        let clip = EditClip(mediaID: item.id, start: placed, sourceIn: 0, sourceOut: item.duration,
                            label: item.name)
        tracks[index].clips.append(clip)
        sortClips(track: index)
        return clip
    }

    @discardableResult
    mutating func insertText(_ style: TextStyle, at time: Double, duration: Double = 4, trackID: UUID? = nil) -> EditClip? {
        var candidates = tracks.indices.filter { tracks[$0].kind == .text && !tracks[$0].isLocked && tracks[$0].role == .standard }
        if let trackID, let i = trackIndex(trackID), tracks[i].kind == .text, !tracks[i].isLocked {
            candidates.insert(i, at: 0)
        }
        for index in candidates where isFree(track: index, start: time, duration: duration) {
            let clip = EditClip.text(style, start: time, duration: duration)
            tracks[index].clips.append(clip)
            sortClips(track: index)
            return clip
        }
        addTrack(.text)
        guard let index = tracks.lastIndex(where: { $0.kind == .text }) else { return nil }
        let clip = EditClip.text(style, start: time, duration: duration)
        tracks[index].clips.append(clip)
        return clip
    }

    mutating func addTrack(_ kind: TrackKind, role: TrackRole = .standard, name: String? = nil) {
        let count = tracks.filter { $0.kind == kind }.count
        let track = EditTrack(kind: kind, name: name ?? "\(kind.label) \(count + 1)", role: role)
        // New video tracks go above existing ones (composited on top); others append.
        if kind == .video, let first = tracks.firstIndex(where: { $0.kind == .video }) {
            tracks.insert(track, at: first)
        } else {
            tracks.append(track)
        }
    }

    // MARK: Split

    /// Splits clips crossing `time`. With `clipIDs` empty, every clip under the playhead on unlocked tracks.
    @discardableResult
    mutating func split(at time: Double, clipIDs: Set<UUID> = []) -> [UUID] {
        var created: [UUID] = []
        for t in tracks.indices where !tracks[t].isLocked {
            var result: [EditClip] = []
            for clip in tracks[t].clips {
                let eligible = clipIDs.isEmpty || clipIDs.contains(clip.id)
                if eligible, time > clip.start + Self.minimumClipDuration, time < clip.end - Self.minimumClipDuration {
                    let (left, right) = clip.split(at: time)
                    result.append(left)
                    result.append(right)
                    created.append(right.id)
                } else {
                    result.append(clip)
                }
            }
            tracks[t].clips = result
        }
        return created
    }

    // MARK: Trim

    /// Moves the clip's left edge to `newStart`, keeping its right edge fixed.
    mutating func trimStart(_ clipID: UUID, to newStart: Double) {
        guard let loc = location(of: clipID), !tracks[loc.track].isLocked else { return }
        let clip = tracks[loc.track].clips[loc.clip]
        let previousEnd = tracks[loc.track].clips.filter { $0.id != clipID && $0.end <= clip.start + 1e-6 }.map(\.end).max() ?? 0
        var lower = previousEnd
        if !clip.isText { lower = max(lower, clip.start - clip.sourceIn / clip.speed) }
        let upper = clip.end - Self.minimumClipDuration
        let start = min(max(newStart, lower), upper)
        var updated = clip
        updated.sourceIn = clip.sourceIn + (start - clip.start) * clip.speed
        updated.start = start
        if clip.isText { updated.sourceIn = 0; updated.sourceOut = clip.end - start }
        tracks[loc.track].clips[loc.clip] = updated
    }

    /// Moves the clip's right edge to `newEnd`.
    mutating func trimEnd(_ clipID: UUID, to newEnd: Double) {
        guard let loc = location(of: clipID), !tracks[loc.track].isLocked else { return }
        let clip = tracks[loc.track].clips[loc.clip]
        let nextStart = tracks[loc.track].clips.filter { $0.id != clipID && $0.start >= clip.end - 1e-6 }.map(\.start).min() ?? .infinity
        var upper = nextStart
        let maxOut = maxSourceOut(for: clip)
        if maxOut.isFinite { upper = min(upper, clip.start + (maxOut - clip.sourceIn) / clip.speed) }
        let end = max(min(newEnd, upper), clip.start + Self.minimumClipDuration)
        tracks[loc.track].clips[loc.clip].sourceOut = clip.sourceIn + (end - clip.start) * clip.speed
    }

    /// Changes playback speed, keeping the start and the source range; fails if the result would overlap.
    @discardableResult
    mutating func setSpeed(_ clipID: UUID, _ speed: Double) -> Bool {
        guard let loc = location(of: clipID), !tracks[loc.track].isLocked else { return false }
        var clip = tracks[loc.track].clips[loc.clip]
        let speed = min(max(speed, 0.25), 4)
        clip.speed = speed
        // Shorten the clip if the slower version no longer fits before the next clip.
        let nextStart = tracks[loc.track].clips.filter { $0.id != clipID && $0.start >= tracks[loc.track].clips[loc.clip].end - 1e-6 }
            .map(\.start).min() ?? .infinity
        if clip.end > nextStart {
            clip.sourceOut = clip.sourceIn + (nextStart - clip.start) * speed
        }
        guard clip.duration >= Self.minimumClipDuration else { return false }
        tracks[loc.track].clips[loc.clip] = clip
        return true
    }

    // MARK: Move

    /// Moves clips by `delta`, optionally onto another track (single clip only).
    /// Returns false (and changes nothing) when the result would overlap or hit a locked track.
    @discardableResult
    mutating func move(_ clipIDs: Set<UUID>, by delta: Double, toTrack targetID: UUID? = nil) -> Bool {
        guard !clipIDs.isEmpty else { return false }
        var copy = self
        var moving: [(track: Int, clip: EditClip)] = []
        for id in clipIDs {
            guard let loc = copy.location(of: id), !copy.tracks[loc.track].isLocked else { return false }
            moving.append((loc.track, copy.tracks[loc.track].clips[loc.clip]))
        }
        for t in copy.tracks.indices { copy.tracks[t].clips.removeAll { clipIDs.contains($0.id) } }

        for item in moving {
            var destination = item.track
            if clipIDs.count == 1, let targetID, let target = copy.trackIndex(targetID) {
                let sourceKind = copy.tracks[item.track].kind
                guard copy.tracks[target].kind == sourceKind || (sourceKind == .audio && copy.tracks[target].kind == .audio) else { return false }
                guard !copy.tracks[target].isLocked else { return false }
                destination = target
            }
            var clip = item.clip
            clip.start = item.clip.start + delta
            guard copy.isFree(track: destination, start: clip.start, duration: clip.duration) else { return false }
            copy.tracks[destination].clips.append(clip)
            copy.sortClips(track: destination)
        }
        self = copy
        return true
    }

    // MARK: Delete

    mutating func delete(_ clipIDs: Set<UUID>) {
        for t in tracks.indices where !tracks[t].isLocked {
            tracks[t].clips.removeAll { clipIDs.contains($0.id) }
        }
    }

    /// Removes `[from, to)` from every unlocked track and closes the gap, keeping all tracks in sync.
    mutating func rippleDelete(from: Double, to: Double) {
        let lower = max(0, min(from, to)), upper = max(from, to)
        let length = upper - lower
        guard length > 1e-4 else { return }
        for t in tracks.indices where !tracks[t].isLocked {
            var result: [EditClip] = []
            for clip in tracks[t].clips {
                if clip.end <= lower + 1e-6 {
                    result.append(clip)
                } else if clip.start >= upper - 1e-6 {
                    var shifted = clip
                    shifted.start -= length
                    result.append(shifted)
                } else {
                    // Overlaps the removed range: keep the parts outside it.
                    if clip.start < lower - Self.minimumClipDuration {
                        result.append(clip.split(at: lower).0)
                    }
                    if clip.end > upper + Self.minimumClipDuration {
                        var right = clip.split(at: upper).1
                        right.start = lower
                        right.transition = nil
                        result.append(right)
                    }
                }
            }
            tracks[t].clips = result.sorted { $0.start < $1.start }
        }
        markers = markers.compactMap { marker in
            if marker.time < lower { return marker }
            if marker.time < upper { return nil }
            var m = marker
            m.time -= length
            return m
        }
    }

    /// Ripple-deletes several ranges, latest first so earlier ranges keep their positions.
    mutating func rippleDelete(ranges: [ClosedRange<Double>]) {
        for range in Self.merge(ranges).reversed() {
            rippleDelete(from: range.lowerBound, to: range.upperBound)
        }
    }

    static func merge(_ ranges: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Double>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.01 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Removes empty space between clips on every unlocked track that starts at `time`.
    mutating func closeGap(at time: Double) {
        let ends = tracks.flatMap(\.clips).filter { $0.end <= time + 1e-6 }.map(\.end)
        let starts = tracks.flatMap(\.clips).filter { $0.start >= time - 1e-6 }.map(\.start)
        guard let gapStart = ends.max(), let gapEnd = starts.min(), gapEnd - gapStart > 1e-3 else { return }
        rippleDelete(from: gapStart, to: gapEnd)
    }

    // MARK: Duplicate

    /// Copies clips right after the originals (or at the end of the track when there is no room).
    @discardableResult
    mutating func duplicate(_ clipIDs: Set<UUID>) -> [UUID] {
        var created: [UUID] = []
        let ordered = clipIDs.compactMap { id in location(of: id).map { (id, $0) } }
            .sorted { tracks[$0.1.track].clips[$0.1.clip].start > tracks[$1.1.track].clips[$1.1.clip].start }
        for (id, _) in ordered {
            guard let loc = location(of: id), !tracks[loc.track].isLocked else { continue }
            var copy = tracks[loc.track].clips[loc.clip]
            copy.id = UUID()
            copy.transition = nil
            let proposed = copy.end
            guard let start = nearestFreeStart(track: loc.track, proposed: proposed, duration: copy.duration) else { continue }
            copy.start = start >= proposed - 1e-6 ? start : trackEnd(loc.track)
            tracks[loc.track].clips.append(copy)
            sortClips(track: loc.track)
            created.append(copy.id)
        }
        return created
    }

    // MARK: Audio

    /// Moves a video clip's sound to its own clip on an audio track; the video clip is muted.
    @discardableResult
    mutating func detachAudio(_ clipID: UUID) -> UUID? {
        guard let loc = location(of: clipID), !tracks[loc.track].isLocked else { return nil }
        let clip = tracks[loc.track].clips[loc.clip]
        guard tracks[loc.track].kind == .video, let media = mediaItem(clip.mediaID), media.hasAudio, !clip.audioMuted else { return nil }
        var audio = clip
        audio.id = UUID()
        audio.transform = ClipTransform()
        audio.crop = ClipCrop()
        audio.fadeIn = 0
        audio.fadeOut = 0
        audio.transition = nil
        audio.label = (clip.label ?? media.name) + tr(" (áudio)")

        let audioTracks = tracks.indices.filter { tracks[$0].kind == .audio && !tracks[$0].isLocked }
        var target = audioTracks.first { isFree(track: $0, start: audio.start, duration: audio.duration) }
        if target == nil {
            addTrack(.audio)
            target = tracks.lastIndex { $0.kind == .audio }
        }
        guard let target, let videoLoc = location(of: clipID) else { return nil }
        tracks[target].clips.append(audio)
        sortClips(track: target)
        tracks[videoLoc.track].clips[videoLoc.clip].audioMuted = true
        return audio.id
    }

    // MARK: Source ↔ timeline mapping

    /// Clips that play `mediaID` (video tracks first), in timeline order.
    func clips(of mediaID: UUID) -> [EditClip] {
        tracks.filter { $0.kind != .text }
            .sorted { $0.kind.displayRank < $1.kind.displayRank }
            .flatMap { $0.clips.filter { $0.mediaID == mediaID } }
    }

    /// Timeline time where media time `s` currently plays, if that part of the media is still used.
    func timelineTime(forSource s: Double, media mediaID: UUID) -> Double? {
        clips(of: mediaID)
            .filter { s >= $0.sourceIn - 1e-6 && s < $0.sourceOut - 1e-6 }
            .map { $0.timelineTime(forSource: s) }
            .min()
    }

    /// Media time of `mediaID` playing at timeline time `t`.
    func sourceTime(atTimeline t: Double, media mediaID: UUID) -> Double? {
        clips(of: mediaID).first { $0.contains(t) }.map { $0.sourceTime(atTimeline: t) }
    }

    /// Timeline ranges where media range `[a, b)` of `mediaID` plays.
    func timelineRanges(forSource a: Double, _ b: Double, media mediaID: UUID) -> [ClosedRange<Double>] {
        var ranges: [ClosedRange<Double>] = []
        for clip in clips(of: mediaID) {
            let lo = max(a, clip.sourceIn), hi = min(b, clip.sourceOut)
            guard hi - lo > 1e-4 else { continue }
            ranges.append(clip.timelineTime(forSource: lo)...clip.timelineTime(forSource: hi))
        }
        return Self.merge(ranges)
    }

    /// Fraction of media range `[a, b)` that is still part of the edit (0 = fully removed).
    func coverage(source a: Double, _ b: Double, media mediaID: UUID) -> Double {
        guard b > a else { return 0 }
        let used = clips(of: mediaID).reduce(0.0) { sum, clip in
            sum + max(0, min(b, clip.sourceOut) - max(a, clip.sourceIn))
        }
        return min(1, used / (b - a))
    }
}

extension EditClip {
    /// Splits at timeline time `t`, returning the left and right parts.
    func split(at t: Double) -> (EditClip, EditClip) {
        var left = self
        var right = self
        right.id = UUID()
        let cut = isText ? (t - start) : sourceTime(atTimeline: t)
        if isText {
            left.sourceOut = cut
            right.sourceIn = 0
            right.sourceOut = duration - cut
        } else {
            left.sourceOut = cut
            right.sourceIn = cut
        }
        right.start = t
        left.fadeOut = 0
        left.audioFadeOut = 0
        right.fadeIn = 0
        right.audioFadeIn = 0
        right.transition = nil
        return (left, right)
    }
}
