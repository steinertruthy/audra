import Foundation
import Testing
@testable import Audra

private func makeProject(duration: Double = 60) -> (EditProject, MediaItem) {
    var project = EditProject(name: "Teste")
    let media = MediaItem(name: "clip", path: "/tmp/clip.mov", duration: duration, hasVideo: true, hasAudio: true, width: 1920, height: 1080)
    project.media.append(media)
    project.insert(media: media, at: 0)
    return (project, media)
}

private func videoClips(_ p: EditProject) -> [EditClip] {
    p.tracks.first { $0.kind == .video }!.clips.sorted { $0.start < $1.start }
}

@Test func splitKeepsSourceContinuity() throws {
    var (p, _) = makeProject()
    let created = p.split(at: 20)
    #expect(created.count == 1)
    let clips = videoClips(p)
    #expect(clips.count == 2)
    #expect(abs(clips[0].sourceOut - 20) < 1e-9)
    #expect(abs(clips[1].sourceIn - 20) < 1e-9)
    #expect(abs(clips[1].start - 20) < 1e-9)
    #expect(abs(p.duration - 60) < 1e-9)
}

@Test func trimIsClampedToMediaAndNeighbours() throws {
    var (p, _) = makeProject()
    p.split(at: 30)
    let clips = videoClips(p)
    // Extending the first clip past its neighbour is not allowed.
    p.trimEnd(clips[0].id, to: 45)
    #expect(abs(videoClips(p)[0].end - 30) < 1e-9)
    // Shortening works and leaves a gap.
    p.trimEnd(clips[0].id, to: 25)
    #expect(abs(videoClips(p)[0].end - 25) < 1e-9)
    // The left edge cannot reveal media before 0.
    p.trimStart(clips[0].id, to: -5)
    #expect(videoClips(p)[0].start >= 0)
    #expect(videoClips(p)[0].sourceIn >= 0)
}

@Test func moveRejectsOverlap() throws {
    var (p, _) = makeProject()
    p.split(at: 30)
    let first = videoClips(p)[0]
    let blocked = p.move([first.id], by: 10)
    #expect(blocked == false)
    #expect(abs(videoClips(p)[0].start) < 1e-9)
    p.trimEnd(first.id, to: 20)
    let moved = p.move([first.id], by: 10)
    #expect(moved)
    #expect(abs(videoClips(p)[0].start - 10) < 1e-9)
}

@Test func rippleDeleteKeepsTracksInSync() throws {
    var (p, media) = makeProject()
    // Music on the audio track spanning the whole video.
    let music = MediaItem(name: "music", path: "/tmp/m.m4a", duration: 120, hasVideo: false, hasAudio: true)
    p.media.append(music)
    p.insert(media: music, at: 0)
    p.rippleDelete(from: 10, to: 25)
    #expect(abs(p.duration - 105) < 1e-6)
    let video = videoClips(p)
    #expect(video.count == 2)
    #expect(abs(video[1].start - 10) < 1e-9)
    #expect(abs(video[1].sourceIn - 25) < 1e-9)
    let audio = p.tracks.first { $0.kind == .audio }!.clips.sorted { $0.start < $1.start }
    #expect(audio.count == 2)
    #expect(abs(audio[1].start - 10) < 1e-9)
    #expect(abs(audio[1].sourceIn - 25) < 1e-9)
    // Mapping: source 30 s now plays at 15 s; source 15 s was removed.
    #expect(abs((p.timelineTime(forSource: 30, media: media.id) ?? -1) - 15) < 1e-9)
    #expect(p.timelineTime(forSource: 15, media: media.id) == nil)
}

@Test func lockedTracksAreNotRippled() throws {
    var (p, _) = makeProject()
    let index = p.tracks.firstIndex { $0.kind == .video }!
    p.tracks[index].isLocked = true
    p.rippleDelete(from: 10, to: 20)
    #expect(videoClips(p).count == 1)
    #expect(abs(p.duration - 60) < 1e-9)
}

@Test func removeSourceRespectsSpeed() throws {
    var (p, media) = makeProject()
    let id = videoClips(p)[0].id
    let changed = p.setSpeed(id, 2)
    #expect(changed)
    #expect(abs(p.duration - 30) < 1e-9)
    // Media 20–30 s plays at timeline 10–15 s at 2×.
    let removed = p.removeSource(20, 30, media: media.id)
    #expect(removed.count == 1)
    #expect(abs(removed[0].lowerBound - 10) < 1e-9 && abs(removed[0].upperBound - 15) < 1e-9)
    #expect(abs(p.duration - 25) < 1e-9)
    #expect(p.coverage(source: 20, 30, media: media.id) < 0.01)
    #expect(p.coverage(source: 0, 20, media: media.id) > 0.99)
}

@Test func duplicateAndDetachAudio() throws {
    var (p, _) = makeProject(duration: 10)
    let id = videoClips(p)[0].id
    let copies = p.duplicate([id])
    #expect(copies.count == 1)
    #expect(abs(p.duration - 20) < 1e-9)
    let audioID = p.detachAudio(id)
    #expect(audioID != nil)
    #expect(p.clip(id)?.audioMuted == true)
    #expect(p.track(containing: audioID!)?.kind == .audio)
    let again = p.detachAudio(id)
    #expect(again == nil) // already detached
}

@Test func subtitlesFollowTheEdit() throws {
    var (p, media) = makeProject()
    let words = [
        TranscriptWord(text: "Olá", start: 1, end: 1.4), TranscriptWord(text: "pessoal.", start: 1.5, end: 2),
        TranscriptWord(text: "Hoje", start: 12, end: 12.4), TranscriptWord(text: "falamos", start: 12.5, end: 13),
    ]
    let segments = [
        TranscriptSegment(start: 1, end: 2, text: "Olá pessoal.", words: Array(words[0...1])),
        TranscriptSegment(start: 12, end: 13, text: "Hoje falamos", words: Array(words[2...3])),
    ]
    p.rippleDelete(from: 5, to: 10)  // second sentence moves from 12 s to 7 s
    let count = p.generateSubtitles(from: segments, media: media.id)
    #expect(count == 2)
    let track = p.tracks.first { $0.role == .subtitles }!
    #expect(abs(track.clips[1].start - 7) < 1e-9)
    #expect(track.clips[0].text?.content == "Olá pessoal.")
    // Regenerating replaces instead of duplicating.
    p.generateSubtitles(from: segments, media: media.id)
    #expect(p.tracks.filter { $0.role == .subtitles }.count == 1)
}

@Test func approximateWordTimingCoversSegment() throws {
    let segment = TranscriptSegment(start: 10, end: 14, text: "um dois três quatro", edited: true)
    let words = segment.timedWords
    #expect(words.count == 4)
    #expect(abs(words.first!.start - 10) < 1e-9)
    #expect(abs(words.last!.end - 14) < 1e-9)
    #expect(words.allSatisfy { $0.approximate })
}

@Test func captionWrapIsBalanced() throws {
    let wrapped = CaptionBuilder.wrap("uma legenda bastante longa que precisa quebrar em duas linhas", lineLength: 42)
    let lines = wrapped.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { $0.count <= 42 })
}

@Test func projectRoundTripsThroughJSON() throws {
    var (p, _) = makeProject()
    p.insertText(.title("Olá"), at: 2)
    p.markers.append(TimelineMarker(time: 3, title: "A"))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(EditProject.self, from: encoder.encode(p))
    #expect(decoded.tracks == p.tracks)
    #expect(decoded.markers == p.markers)
    #expect(decoded.canvas == p.canvas)
}

@Test func segmentBuilderKeepsWordTiming() throws {
    let pieces = [
        RecognizedPiece(text: "Bom", start: 0, end: 0.3, confidence: 0.9),
        RecognizedPiece(text: " dia", start: 0.35, end: 0.6, confidence: 0.9),
    ]
    let segments = SegmentBuilder.build(pieces: pieces, fallbackStart: 0, fallbackEnd: 1)
    #expect(segments.first?.words?.map(\.text) == ["Bom", "dia"])
    #expect(segments.first?.words?.first?.approximate == false)
}

@Test func subtitlesDropRemovedWords() throws {
    var (p, media) = makeProject()
    let words = ["um", "dois", "três", "quatro"].enumerated().map { i, w in
        TranscriptWord(text: w, start: Double(i), end: Double(i) + 0.8)
    }
    let segment = TranscriptSegment(start: 0, end: 3.8, text: "um dois três quatro", words: words)
    p.removeSource(1, 1.9, media: media.id)   // removes "dois"
    p.generateSubtitles(from: [segment], media: media.id)
    let texts = p.tracks.first { $0.role == .subtitles }!.clips.compactMap { $0.text?.content }
    #expect(!texts.joined(separator: " ").contains("dois"))
    #expect(texts.joined(separator: " ").contains("três"))
}

@Test func interfaceTranslationsFillPlaceholders() throws {
    Localization.shared.use("en")
    #expect(tr("Transcrevendo “%@” em %@…", "a", "b") == "Transcribing “a” in b…")
    Localization.shared.use("es")
    #expect(tr("Projetos") == "Proyectos")
    Localization.shared.use("pt")
    #expect(tr("Projetos") == "Projetos")
    #expect(tr("Texto inexistente %@", 1) == "Texto inexistente 1")
}
