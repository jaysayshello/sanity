import Foundation

/// Parses and serializes the task list to/from a plain markdown file.
///
/// Format (one task per `##` heading):
///
///     # Tasks
///
///     ## Ship the widget app
///     Get v1 building and running
///
///     Longer context in markdown, as many lines as you want.
///
///     ## [x] Something already finished
///     Short summary line
///
/// - A `[x]` (or `[X]`) right after `##` marks the task done; `[ ]` or nothing means open.
/// - The first non-empty line under the heading is the card summary.
/// - Everything after that is the detailed context shown in the popover.
enum MarkdownStore {
    static func parse(_ text: String) -> [TaskItem] {
        var tasks: [TaskItem] = []
        var currentTitle: String?
        var currentDone = false
        var currentSummarized = false
        var currentBody: [String] = []

        func flush() {
            guard let title = currentTitle else { return }
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .newlines)
            tasks.append(TaskItem(title: title, done: currentDone, body: body, summarized: currentSummarized))
            currentTitle = nil
            currentDone = false
            currentSummarized = false
            currentBody = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine
            if line.hasPrefix("## ") {
                flush()
                var heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var done = false
                if heading.hasPrefix("[x]") || heading.hasPrefix("[X]") {
                    done = true
                    heading = String(heading.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if heading.hasPrefix("[ ]") {
                    heading = String(heading.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                currentTitle = heading
                currentDone = done
            } else if line.hasPrefix("# ") {
                // Top-level document title, ignored.
                continue
            } else if currentTitle != nil {
                if line.trimmingCharacters(in: .whitespaces) == "<!-- summarized -->" {
                    currentSummarized = true
                } else {
                    currentBody.append(line)
                }
            }
        }
        flush()
        return tasks
    }

    static func serialize(_ tasks: [TaskItem]) -> String {
        var out = "# Tasks\n"
        for task in tasks {
            let mark = task.done ? "[x] " : ""
            out += "\n## \(mark)\(task.title)\n"
            if task.summarized {
                out += "<!-- summarized -->\n"
            }
            let body = task.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                out += body + "\n"
            }
        }
        return out
    }
}
