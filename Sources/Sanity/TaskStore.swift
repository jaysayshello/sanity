import Foundation
import Combine
import AppKit

/// Owns the task list, the markdown file on disk, and user settings.
/// Loads on launch, writes back on every mutation, and polls the file
/// so edits made in an external editor show up in the widget.
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = []
    @Published var opacity: Double {
        didSet { UserDefaults.standard.set(opacity, forKey: "windowOpacity") }
    }
    /// Size multiplier for the whole widget (1.0 == 100%).
    @Published var scale: Double {
        didSet {
            let clamped = min(max(scale, 0.5), 3.0)
            if clamped != scale { scale = clamped; return }
            UserDefaults.standard.set(scale, forKey: "widgetScale")
        }
    }
    @Published var hideDone: Bool {
        didSet { UserDefaults.standard.set(hideDone, forKey: "hideDone") }
    }
    /// When locked, the widget can't be dragged around.
    @Published var locked: Bool {
        didSet { UserDefaults.standard.set(locked, forKey: "locked") }
    }

    // MARK: - AI (Bedrock) settings
    @Published var aiEnabled: Bool {
        didSet {
            UserDefaults.standard.set(aiEnabled, forKey: "aiEnabled")
            summarizePendingIfNeeded()
        }
    }
    @Published var aiToken: String {
        didSet {
            UserDefaults.standard.set(aiToken, forKey: "aiToken")
            summarizePendingIfNeeded()
        }
    }
    @Published var aiBaseURL: String {
        didSet { UserDefaults.standard.set(aiBaseURL, forKey: "aiBaseURL") }
    }
    @Published var aiModel: String {
        didSet { UserDefaults.standard.set(aiModel, forKey: "aiModel") }
    }

    /// AI actions are usable only when enabled and a key is present.
    var aiAvailable: Bool {
        aiEnabled && !aiToken.trimmingCharacters(in: .whitespaces).isEmpty
    }

    let fileURL: URL
    private var pollTimer: Timer?
    private var lastModified: Date?
    private var suppressReloadUntil: Date = .distantPast

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.double(forKey: "windowOpacity")
        self.opacity = saved == 0 ? 0.75 : saved
        let savedScale = defaults.double(forKey: "widgetScale")
        self.scale = savedScale == 0 ? 1.4 : savedScale
        self.hideDone = defaults.bool(forKey: "hideDone")
        self.locked = defaults.bool(forKey: "locked")
        // AI defaults come from the local config file (not hardcoded), and are
        // overridden by anything set in-app (UserDefaults).
        let config = AppConfig.load()
        self.aiEnabled = defaults.bool(forKey: "aiEnabled")
        self.aiToken = defaults.string(forKey: "aiToken") ?? config.aiToken ?? ""
        self.aiBaseURL = defaults.string(forKey: "aiBaseURL") ?? config.aiBaseURL ?? ""
        self.aiModel = defaults.string(forKey: "aiModel") ?? config.aiModel ?? ""

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/sanity", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("tasks.md")

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let seed = MarkdownStore.serialize([
                TaskItem(title: "task 1", body: "five word summary here\n\nClick to add context."),
                TaskItem(title: "task 2", body: "another short summary line\n\nMore detail lives here."),
                TaskItem(title: "task 3", body: "third task summary text\n\nEdit me in the popover.")
            ])
            try? seed.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        load()
        startPolling()
    }

    // MARK: - File IO

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        tasks = MarkdownStore.parse(text)
        lastModified = fileModifiedDate()
        summarizePendingIfNeeded()
    }

    private func save() {
        let text = MarkdownStore.serialize(tasks)
        // Ignore the file-change we are about to cause for a short window.
        suppressReloadUntil = Date().addingTimeInterval(1.0)
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        lastModified = fileModifiedDate()
    }

    private func fileModifiedDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attrs?[.modificationDate] as? Date
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if Date() < self.suppressReloadUntil { return }
            let current = self.fileModifiedDate()
            if current != self.lastModified {
                self.load()
            }
        }
    }

    // MARK: - Mutations

    func toggleDone(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].done.toggle()
        save()
    }

    func updateContext(_ task: TaskItem, title: String, body: String, summarized: Bool? = nil) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].title = title
        tasks[idx].body = body
        if let summarized {
            tasks[idx].summarized = summarized
            // A manual edit clears the failure memory so the AI can retry.
            if !summarized { failedSummaries.remove(task.id) }
        }
        save()
        // Re-run the AI if this edit marked the task unsummarized.
        summarizePendingIfNeeded()
    }

    func addTask(title: String = "new task", body: String = "", summarized: Bool = false) {
        tasks.append(TaskItem(title: title, body: body, summarized: summarized))
        save()
        summarizePendingIfNeeded()
    }

    func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    /// Reorder: move the dragged task into the target's slot, shifting the rest
    /// (an insert, not a swap). Works the same dragging left or right.
    func moveTask(_ draggedID: UUID, onto targetID: UUID) {
        guard draggedID != targetID,
              let from = tasks.firstIndex(where: { $0.id == draggedID }),
              let to = tasks.firstIndex(where: { $0.id == targetID }) else { return }
        let item = tasks.remove(at: from)
        tasks.insert(item, at: min(to, tasks.count))
        save()
    }

    func openInEditor() {
        NSWorkspace.shared.open(fileURL)
    }

    // MARK: - Auto AI summarization

    private var summarizing = false
    /// Tasks currently being summarized, so cards can show a live placeholder.
    @Published var summarizingIDs: Set<UUID> = []
    /// Tasks that failed to summarize this session, so we don't retry in a loop.
    private var failedSummaries: Set<UUID> = []

    private func summaryMaterial(for task: TaskItem) -> String {
        [task.title, task.summary, task.context]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Summarize every task that hasn't been summarized yet (new or pre-existing),
    /// one at a time, then mark each so it never re-runs.
    func summarizePendingIfNeeded() {
        guard aiAvailable, !summarizing else { return }
        let pending = tasks.filter {
            !$0.summarized && !failedSummaries.contains($0.id) && !summaryMaterial(for: $0).isEmpty
        }
        guard !pending.isEmpty else { return }
        let ids = pending.map { $0.id }
        summarizing = true
        Task { @MainActor in
            defer { self.summarizing = false }
            for id in ids {
                guard let task = self.tasks.first(where: { $0.id == id }), !task.summarized else { continue }
                self.summarizingIDs.insert(id)
                do {
                    let result = try await AIService.summarize(
                        context: self.summaryMaterial(for: task),
                        token: self.aiToken,
                        baseURL: self.aiBaseURL,
                        model: self.aiModel
                    )
                    self.applyAISummary(taskID: id, title: result.title, preview: result.summary)
                } catch {
                    self.failedSummaries.insert(id)
                }
                self.summarizingIDs.remove(id)
            }
        }
    }

    private func applyAISummary(taskID: UUID, title: String, preview: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        // Tasks enter summarization with the full notes as the body (no preview
        // line yet), so keep all of it and just prepend the AI preview.
        let notes = tasks[idx].body.trimmingCharacters(in: .whitespacesAndNewlines)
        tasks[idx].title = title
        tasks[idx].body = [preview, notes].filter { !$0.isEmpty }.joined(separator: "\n\n")
        tasks[idx].summarized = true
        save()
    }
}
