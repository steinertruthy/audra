import Foundation

/// Optional cloud summarizer using the Anthropic Messages API.
/// Only used when the user selected it AND explicitly consented to sending the transcript.
/// The whole transcript fits the model context, so a single request is made.
struct ClaudeSummarizer: Summarizer {
    static let defaultModel = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var model: String
    var displayName: String { "Claude (\(model))" }

    func summarize(_ request: SummaryRequest, progress: @escaping @Sendable (Double) -> Void) async throws -> VideoSummary {
        guard Preferences.claudeConsent else { throw SummaryError.consentRequired }
        guard let key = Keychain.read(), !key.isEmpty else { throw SummaryError.missingAPIKey }
        guard !request.segments.isEmpty else { throw SummaryError.emptyTranscript }
        progress(0.05)

        let duration = request.segments.last?.end ?? 0
        let prompt = """
        Transcrição automática do vídeo "\(request.title)" (duração \(TimeFormat.clock(duration))). \
        Cada linha começa com o instante [mm:ss] em que o trecho é falado.

        <transcricao>
        \(TranscriptChunker.fullText(request.segments))
        </transcricao>

        Gere o resumo estruturado. \(request.detail.guidance)
        Para "chapters", divida o vídeo em seções na ordem cronológica, usando como start_seconds o instante \
        de uma linha existente da transcrição. Para vídeos curtos (menos de 3 minutos), retorne chapters vazio.
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16_000,
            "system": SummaryPrompts.faithfulnessRules(language: request.languageName),
            "messages": [["role": "user", "content": prompt]],
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.schema],
            ],
            "fallbacks": "default",
        ]

        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: 600)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(urlRequest, attempts: 3)
        progress(0.95)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SummaryError.invalidResponse }
        if (json["stop_reason"] as? String) == "refusal" { throw SummaryError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payload = text.data(using: .utf8)
        else { throw SummaryError.invalidResponse }

        let decoded = try JSONDecoder().decode(Payload.self, from: payload)
        progress(1)
        return VideoSummary(
            overview: decoded.overview,
            topics: decoded.topics,
            keyPoints: decoded.key_points,
            decisions: decoded.decisions,
            actionItems: decoded.action_items,
            chapters: decoded.chapters
                .filter { $0.start_seconds >= 0 && $0.start_seconds <= duration + 1 }
                .sorted { $0.start_seconds < $1.start_seconds }
                .map { SummaryChapter(start: $0.start_seconds, title: $0.title) },
            provider: displayName,
            detail: request.detail
        )
    }

    private func send(_ request: URLRequest, attempts: Int) async throws -> Data {
        var lastError: Error = SummaryError.invalidResponse
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return data }
                let message = Self.errorMessage(from: data) ?? "HTTP \(status)"
                switch status {
                case 401: throw SummaryError.api("chave de API inválida.")
                case 429, 500...599:
                    lastError = SummaryError.api(message)
                    try await Task.sleep(for: .seconds(Double(2 << attempt)))
                    continue
                default: throw SummaryError.api(message)
                }
            } catch let error as URLError where error.code != .cancelled {
                lastError = SummaryError.api(error.localizedDescription)
                try await Task.sleep(for: .seconds(Double(2 << attempt)))
            }
        }
        throw lastError
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    private struct Payload: Decodable {
        struct Chapter: Decodable { var start_seconds: Double; var title: String }
        var overview: String
        var topics: [String]
        var key_points: [String]
        var decisions: [String]
        var action_items: [String]
        var chapters: [Chapter]
    }

    private static let schema: [String: Any] = {
        let stringArray: [String: Any] = ["type": "array", "items": ["type": "string"]]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["overview", "topics", "key_points", "decisions", "action_items", "chapters"],
            "properties": [
                "overview": ["type": "string", "description": "Visão geral clara do assunto"],
                "topics": stringArray,
                "key_points": stringArray,
                "decisions": stringArray,
                "action_items": stringArray,
                "chapters": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["start_seconds", "title"],
                        "properties": [
                            "start_seconds": ["type": "number"],
                            "title": ["type": "string"],
                        ],
                    ],
                ],
            ],
        ]
    }()
}
