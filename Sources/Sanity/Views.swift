import SwiftUI

/// Solid (non-blurred) card fill. A plain color renders instantly on Space
/// switches, unlike a material, which recomposites against each wallpaper.
enum WidgetPalette {
    static let card = Color(red: 0.11, green: 0.12, blue: 0.16)
}

/// The floating row of square task cards plus a small toolbar.
struct WidgetView: View {
    @ObservedObject var store: TaskStore
    @State private var showingSettings = false

    /// Uniform size multiplier for the whole widget, driven by the settings
    /// slider. Tuned so the row fills the strip between the menu bar and the
    /// window below it.
    private var scale: CGFloat { CGFloat(store.scale) }
    private var cardSize: CGFloat { 116 * scale }
    private var spacing: CGFloat { 14 * scale }

    private var visibleTasks: [TaskItem] {
        store.hideDone ? store.tasks.filter { !$0.done } : store.tasks
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(visibleTasks) { task in
                TaskCardView(task: task, store: store, size: cardSize, scale: scale)
            }
            AddCardView(size: cardSize, scale: scale, store: store)
            toolbar
        }
        .padding(.horizontal, spacing)
        .padding(.vertical, 12)
        .background(Color.clear)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: visibleTasks.map(\.id))
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            Image(systemName: store.locked ? "lock.fill" : "line.3.horizontal")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(.secondary)
                .help(store.locked ? "Locked (unlock in settings)" : "Drag to move")
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13 * scale, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Transparency & file")
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                SettingsView(store: store)
            }
            Spacer()
        }
        .frame(width: 22 * scale)
        .padding(.top, 4 * scale)
    }
}

struct TaskCardView: View {
    let task: TaskItem
    @ObservedObject var store: TaskStore
    let size: CGFloat
    var scale: CGFloat = 1
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openEditor, object: task.id.uuidString)
        } label: {
            VStack(alignment: .leading, spacing: 6 * scale) {
                HStack(alignment: .top, spacing: 6 * scale) {
                    Button {
                        store.toggleDone(task)
                    } label: {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14 * scale, weight: .semibold))
                            .foregroundStyle(task.done ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(task.title)
                        .font(.system(size: 14 * scale, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .strikethrough(task.done, color: .secondary)
                }
                let isSummarizing = store.summarizingIDs.contains(task.id)
                Text(isSummarizing ? "\u{1F916} Summarizing\u{2026}" : task.summary)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(.secondary)
                    .italic(isSummarizing)
                    .lineLimit(3)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
            }
            .padding(10 * scale)
            .frame(width: size, height: size, alignment: .topLeading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12 * scale)
                    .strokeBorder(Color.white.opacity(hovering ? 0.35 : 0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
            .contentShape(RoundedRectangle(cornerRadius: 12 * scale))
            .opacity(task.done ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .scaleEffect(dropTargeted ? 1.06 : 1)
        .animation(.spring(response: 0.16, dampingFraction: 0.82), value: dropTargeted)
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let dragged = UUID(uuidString: first) else { return false }
            store.moveTask(dragged, onto: task.id)
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Open detail") {
                NotificationCenter.default.post(name: .openEditor, object: task.id.uuidString)
            }
            Button(task.done ? "Mark open" : "Mark done") { store.toggleDone(task) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteTask(task) }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12 * scale)
            .fill(WidgetPalette.card.opacity(store.opacity))
    }
}

struct AddCardView: View {
    let size: CGFloat
    var scale: CGFloat = 1
    @ObservedObject var store: TaskStore
    @State private var hovering = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openNewEditor, object: nil)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22 * scale, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 12 * scale)
                        .fill(WidgetPalette.card.opacity(store.opacity * (hovering ? 0.85 : 0.5)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12 * scale)
                        .strokeBorder(
                            Color.white.opacity(hovering ? 0.4 : 0.2),
                            style: StrokeStyle(lineWidth: 1, dash: [5 * scale])
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Add a task")
    }
}

/// Large, centered editor window for creating or editing a task. Opened by
/// AppDelegate in its own panel, with a connector line drawn back to the card.
struct EditorView: View {
    @ObservedObject var store: TaskStore
    let taskID: UUID?
    let onClose: () -> Void

    @State private var title: String = ""
    @State private var preview: String = ""
    @State private var context: String = ""
    @State private var aiBusy = false
    @State private var aiError: String?
    @State private var aiApplied = false
    @State private var didPersist = false
    @State private var origTitle = ""
    @State private var origPreview = ""
    @State private var origContext = ""
    @FocusState private var titleFocused: Bool

    private var isNew: Bool { taskID == nil }
    private var task: TaskItem? { taskID.flatMap { id in store.tasks.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(isNew ? "New task" : "Edit task")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if store.aiAvailable {
                    Button {
                        Task { await runAI() }
                    } label: {
                        HStack(spacing: 5) {
                            if aiBusy {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(aiBusy ? "Summarizing\u{2026}" : "AI summarize")
                        }
                    }
                    .disabled(aiBusy)
                    .help("Summarize the notes and set the title with Bedrock")
                }
            }

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 26, weight: .bold))
                .focused($titleFocused)

            TextField("Preview (card summary)", text: $preview)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            if let aiError {
                Text(aiError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $context)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 220)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))

            HStack(spacing: 10) {
                if !isNew {
                    Button((task?.done ?? false) ? "Mark open" : "Mark done") {
                        if let t = task { store.toggleDone(t) }
                    }
                }
                Spacer()
                if isNew {
                    Button("Cancel") { onClose() }
                        .keyboardShortcut(.cancelAction)
                    Button("Add") { add() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSubmit)
                } else {
                    Button("Open in editor") { store.openInEditor() }
                    Button("Done") { persistEdit(); onClose() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
            .font(.system(size: 14))
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16).fill(WidgetPalette.card.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.14)))
        .onExitCommand { if !isNew { persistEdit() }; onClose() }
        .onAppear { load(); titleFocused = true }
        .onDisappear { if !isNew { persistEdit() } }
    }

    private func load() {
        guard let t = task else { return }
        title = t.title
        preview = t.summary
        context = t.context
        origTitle = title
        origPreview = preview
        origContext = context
    }

    /// Body stored as "<preview>\n\n<notes>", so the first line is the card summary.
    private var composedBody: String {
        [preview.trimmingCharacters(in: .whitespacesAndNewlines),
         context.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// In AI mode a title isn't required (the AI fills it); otherwise it is.
    private var canSubmit: Bool {
        let hasTitle = !title.trimmingCharacters(in: .whitespaces).isEmpty
        guard store.aiAvailable else { return hasTitle }
        return hasTitle
            || !preview.trimmingCharacters(in: .whitespaces).isEmpty
            || !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        guard canSubmit else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        // Placeholder title when AI mode leaves it blank; the AI replaces it.
        let finalTitle = trimmed.isEmpty ? "\u{2026}" : trimmed
        store.addTask(title: finalTitle, body: composedBody, summarized: aiApplied)
        onClose()
    }

    private func persistEdit() {
        guard let t = task, !didPersist else { return }
        didPersist = true
        let changed = title != origTitle || preview != origPreview || context != origContext
        let notes = context.trimmingCharacters(in: .whitespacesAndNewlines)

        if aiApplied {
            // Used the AI button: keep its preview above the notes.
            store.updateContext(t, title: title, body: composedBody, summarized: true)
        } else if changed && store.aiAvailable {
            // Manual change with AI on: store just the notes so the AI can
            // regenerate the preview from them (without losing any text).
            store.updateContext(t, title: title, body: notes, summarized: false)
        } else {
            store.updateContext(t, title: title, body: composedBody, summarized: nil)
        }
    }

    @MainActor
    private func runAI() async {
        aiError = nil
        aiBusy = true
        if let taskID { store.summarizingIDs.insert(taskID) }
        defer {
            aiBusy = false
            if let taskID { store.summarizingIDs.remove(taskID) }
        }
        let material = [preview, context]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        do {
            let result = try await AIService.summarize(
                context: material,
                token: store.aiToken,
                baseURL: store.aiBaseURL,
                model: store.aiModel
            )
            title = result.title
            preview = result.summary
            aiApplied = true
        } catch {
            aiError = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: TaskStore

    /// Slider and text field both edit the size as a percent (100% == 1.0).
    private var percent: Binding<Double> {
        Binding(
            get: { store.scale * 100 },
            set: { store.scale = $0 / 100 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 15, weight: .bold))

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Appearance")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Size").font(.system(size: 12))
                        Spacer()
                        TextField("", value: percent, format: .number.precision(.fractionLength(0...1)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                        Text("%").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Slider(value: percent, in: 50...300)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transparency").font(.system(size: 12))
                    Slider(value: $store.opacity, in: 0.2...1.0)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Behavior")
                Toggle("Hide completed tasks", isOn: $store.hideDone)
                Toggle("Lock position", isOn: $store.locked)
            }
            .toggleStyle(.checkbox)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("AI")
                Toggle("Enable AI", isOn: $store.aiEnabled)
                    .toggleStyle(.checkbox)
                if store.aiEnabled {
                    SecureField("API key (sk-\u{2026})", text: $store.aiToken)
                        .textFieldStyle(.roundedBorder)
                    TextField("API base URL", text: $store.aiBaseURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $store.aiModel)
                        .textFieldStyle(.roundedBorder)
                    Text("Summarizes notes and picks a title: fix, monitor, notify, triage, mitigate, review.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Widget")
                HStack(spacing: 8) {
                    Button("Center on top") {
                        NotificationCenter.default.post(name: .centerWidget, object: nil)
                    }
                    .frame(maxWidth: .infinity)
                    Button("Save location") {
                        NotificationCenter.default.post(name: .saveWidgetLocation, object: nil)
                    }
                    .frame(maxWidth: .infinity)
                }
                Button("Open tasks.md") { store.openInEditor() }
                    .frame(maxWidth: .infinity)
                Text(store.fileURL.path)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(width: 272)
        .padding(18)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}
