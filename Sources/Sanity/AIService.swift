import Foundation

struct AISummary {
    let title: String
    let summary: String
}

/// Result of organizing raw standup notes: a "<emoji> Standup" title whose
/// emoji reflects the day's focus, a short card preview, and the notes
/// rewritten as bullet points.
struct StandupResult {
    let title: String
    let summary: String
    let bullets: String
}

/// Calls an OpenAI-compatible Chat Completions endpoint (OpenAI, a LiteLLM
/// gateway, OpenWebUI, etc.) to categorize a task and write a short card
/// preview. Auth is a bearer key (the `sk-...` style token).
enum AIService {
    /// Allowed card titles. The model must pick exactly one.
    static let categories = ["fix", "monitor", "notify", "triage", "mitigate", "review", "life"]

    /// Emoji shown before each title.
    static let emoji: [String: String] = [
        "fix": "\u{1F527}",
        "monitor": "\u{1F4C8}",
        "notify": "\u{1F514}",
        "triage": "\u{1F50D}",
        "mitigate": "\u{1F6E1}",
        "review": "\u{1F4DD}",
        "life": "\u{1F331}",
    ]

    /// Max words in the generated card preview. Kept short so the card never
    /// needs to truncate with an ellipsis.
    static let summaryWordLimit = 6

    /// Fixed emoji shown on every standup card title.
    static let standupEmoji = "\u{1FAE1}"  // saluting face

    enum AIError: LocalizedError {
        case notConfigured
        case badURL
        case http(Int, String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add an API key in settings first."
            case .badURL: return "Invalid API base URL."
            case .http(let code, let body): return "API error \(code): \(body.prefix(200))"
            case .emptyResponse: return "The model returned no usable text."
            }
        }
    }

    static func summarize(context: String, token: String, baseURL: String, model: String) async throws -> AISummary {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AIError.notConfigured }

        let model = model.trimmingCharacters(in: .whitespaces)
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/chat/completions") else { throw AIError.badURL }

        let system = """
        You label and summarize a task for a small sticky-note widget.
        Pick exactly one title from this list that best fits the task: \(categories.joined(separator: ", ")).
        Write a preview summary of at most \(summaryWordLimit) words: plain, specific, no trailing period, no quotes.
        Respond with ONLY minified JSON, no code fences: {"title":"<one of the list>","summary":"<preview>"}
        """
        let userText = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no details provided)"
            : context

        let text = try await complete(
            system: system, user: userText, url: url,
            token: token, model: model, maxTokens: 150
        )
        let json = extractJSON(from: text)
        let parsed = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]

        var category = (parsed?["title"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        if !categories.contains(category) { category = "fix" }
        // Non-breaking space keeps the emoji and word on one line on the card.
        let title = "\(emoji[category] ?? "")\u{00A0}\(category.capitalized)".trimmingCharacters(in: .whitespaces)

        var summary = (parsed?["summary"] as? String ?? text).trimmingCharacters(in: .whitespacesAndNewlines)
        summary = clampWords(summary, to: summaryWordLimit)

        return AISummary(title: title, summary: summary)
    }

    /// Organize raw standup notes into a daily standup: a bulleted rewrite of
    /// the notes plus an emoji that represents what the day is focused on.
    static func organizeStandup(context: String, token: String, baseURL: String, model: String) async throws -> StandupResult {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AIError.notConfigured }

        let model = model.trimmingCharacters(in: .whitespaces)
        var base = baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: "\(base)/chat/completions") else { throw AIError.badURL }

        let system = """
        You organize a person's raw standup notes into their daily standup.
        Rewrite the notes as short, specific markdown bullet points, one item per bullet.
        Only reorganize what is given: do not invent work, and keep the original meaning.
        If the notes clearly separate finished, planned, and blocked work, order them that way; do not add headers.
        Write a preview of at most \(summaryWordLimit) words summarizing the day: plain, specific, no bullet, no trailing period, no quotes.
        Respond with ONLY minified JSON, no code fences: {"summary":"<preview>","bullets":["<item>","<item>"]}
        """
        let userText = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(no details provided)"
            : context

        let text = try await complete(
            system: system, user: userText, url: url,
            token: token, model: model, maxTokens: 500
        )
        let json = extractJSON(from: text)
        let parsed = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]

        let title = "\(standupEmoji)\u{00A0}Standup"

        var summary = (parsed?["summary"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        summary = clampWords(summary, to: summaryWordLimit)
        if summary.isEmpty { summary = "Daily standup" }

        let items = (parsed?["bullets"] as? [String]) ?? []
        let bullets = bulletList(from: items, fallback: text)
        return StandupResult(title: title, summary: summary, bullets: bullets)
    }

    /// Turn model items into a clean markdown bullet list. Falls back to the
    /// raw response (split into lines) if the JSON had no usable array.
    private static func bulletList(from items: [String], fallback: String) -> String {
        var lines = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.isEmpty {
            lines = fallback
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return lines
            .map { line in
                var item = line
                while item.hasPrefix("-") || item.hasPrefix("*") || item.hasPrefix("\u{2022}") {
                    item.removeFirst()
                    item = item.trimmingCharacters(in: .whitespaces)
                }
                return "- \(item)"
            }
            .joined(separator: "\n")
    }

    /// Shared Chat Completions call. Returns the assistant message text.
    private static func complete(system: String, user: String, url: URL, token: String, model: String, maxTokens: Int) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = obj?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = (message?["content"] as? String) ?? ""
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }

    /// Pull the first {...} object out of a model response (handles stray prose or fences).
    private static func extractJSON(from text: String) -> String {
        guard let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close else {
            return text
        }
        return String(text[open...close])
    }

    private static func clampWords(_ text: String, to limit: Int) -> String {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard words.count > limit else { return text }
        return words.prefix(limit).joined(separator: " ")
    }
}
