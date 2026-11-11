import Testing
@testable import Audra

struct FormattingTests {
    @Test func clockFormats() {
        #expect(TimeFormat.clock(0) == "00:00")
        #expect(TimeFormat.clock(65.9) == "01:05")
        #expect(TimeFormat.clock(3723) == "1:02:03")
        #expect(TimeFormat.clock(.nan) == "00:00")
    }

    @Test func srtTimestamps() {
        #expect(TimeFormat.srt(0) == "00:00:00,000")
        #expect(TimeFormat.srt(3661.257) == "01:01:01,257")
    }

    @Test func diacriticInsensitiveSearch() {
        let text = "A reunião de Revisão foi ótima; revisao final amanhã."
        #expect(text.ranges(of: "revisao").count == 2)
        #expect(text.matches("OTIMA"))
        #expect(text.ranges(of: "").isEmpty)
    }
}

struct SegmentBuilderTests {
    private func words(_ text: String, start: Double, step: Double = 0.4) -> [RecognizedPiece] {
        text.split(separator: " ").enumerated().map { i, w in
            let s = start + Double(i) * step
            return RecognizedPiece(text: (i == 0 ? "" : " ") + w, start: s, end: s + step * 0.9, confidence: 0.9)
        }
    }

    @Test func splitsAtSentenceBoundaryAfterMinimumLength() {
        let pieces = words("um dois três quatro cinco seis sete oito nove dez onze. doze treze catorze.", start: 10)
        let segments = SegmentBuilder.build(pieces: pieces, fallbackStart: 10, fallbackEnd: 20)
        #expect(segments.count == 2)
        #expect(segments[0].text.hasSuffix("onze."))
        #expect(segments[0].start == 10)
        #expect(segments[1].text == "doze treze catorze.")
        #expect(abs((segments[0].confidence ?? 0) - 0.9) < 0.001)
    }

    @Test func forceSplitsLongRunsWithoutPunctuation() {
        let long = Array(repeating: "palavra", count: 120).joined(separator: " ")
        let segments = SegmentBuilder.build(pieces: words(long, start: 0), fallbackStart: 0, fallbackEnd: 48)
        #expect(segments.count >= 3)
        #expect(segments.allSatisfy { $0.duration <= SegmentBuilder.hardMaximum + 0.5 })
    }

    @Test func splitsOnLongPause() throws {
        let first = words("isto é uma frase sem ponto final que dura bastante", start: 0, step: 0.5)
        let second = words("e esta começa depois de uma pausa", start: 8)
        let segments = SegmentBuilder.build(pieces: first + second, fallbackStart: 0, fallbackEnd: 12)
        try #require(segments.count == 2)
        #expect(segments[1].start == 8)
    }

    @Test func fallsBackToResultRangeWithoutTimings() {
        let pieces = [RecognizedPiece(text: "Olá mundo", start: nil, end: nil, confidence: nil)]
        let segments = SegmentBuilder.build(pieces: pieces, fallbackStart: 3, fallbackEnd: 5)
        #expect(segments == [TranscriptSegment(id: segments[0].id, start: 3, end: 5, text: "Olá mundo")])
    }
}

struct ChunkerAndExportTests {
    let segments = (0..<50).map { TranscriptSegment(start: Double($0) * 5, end: Double($0) * 5 + 4, text: "Trecho número \($0) com algum conteúdo falado.") }

    @Test func chunksRespectLimitAndOrder() {
        let chunks = TranscriptChunker.chunks(segments, maxCharacters: 400)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.text.count <= 400 })
        #expect(chunks.map(\.start) == chunks.map(\.start).sorted())
        #expect(chunks.first?.start == 0)
        #expect(chunks.last?.end == segments.last?.end)
    }

    @Test func srtIsWellFormed() {
        let srt = TranscriptRenderer.srt(segments: Array(segments.prefix(2)))
        #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:04,000\nTrecho número 0"))
        #expect(srt.contains("\n\n2\n00:00:05,000 --> 00:00:09,000\n"))
    }

    @Test func summaryMarkdownMarksEmptySectionsAndDisclaimer() {
        Localization.shared.use("pt")
        let summary = VideoSummary(overview: "Visão.", topics: ["A"], keyPoints: [], decisions: [], actionItems: ["Fazer X"],
                                   chapters: [SummaryChapter(start: 65, title: "Início")], provider: "Teste", detail: .standard)
        let md = TranscriptRenderer.summaryMarkdown(title: "Vídeo", meta: "1 min", summary: summary)
        #expect(md.contains("## Decisões e conclusões\n\n_Nenhuma decisão identificada no conteúdo._"))
        #expect(md.contains("- **01:05** Início"))
        #expect(md.contains("- Fazer X"))
        #expect(md.contains("gerado automaticamente por IA"))
        #expect(!md.contains("## Pontos importantes"))
    }
}
