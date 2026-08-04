import Foundation

/// One task = one card. Backed by a `##` section in the markdown file.
struct TaskItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var done: Bool
    /// Full markdown body after the heading (summary line + context).
    var body: String
    /// Whether the AI has already generated the title + preview for this task.
    var summarized: Bool

    init(id: UUID = UUID(), title: String, done: Bool = false, body: String = "", summarized: Bool = false) {
        self.id = id
        self.title = title
        self.done = done
        self.body = body
        self.summarized = summarized
    }

    /// First non-empty line of the body, used as the ~5-word card summary.
    var summary: String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    /// Body with the summary line removed, i.e. the detailed context.
    var context: String {
        let lines = body.components(separatedBy: "\n")
        var removedSummary = false
        var result: [String] = []
        for line in lines.indices {
            let trimmed = lines[line].trimmingCharacters(in: .whitespaces)
            if !removedSummary {
                if trimmed.isEmpty { continue }
                removedSummary = true
                continue
            }
            result.append(lines[line])
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
