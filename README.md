# Task Widgets

A small, fast, native SwiftUI macOS app that floats a row of square task
cards at the top-left of the desktop. Each card is one task: a title plus a
short summary. Click a card to open a fast popover with the full context.
The whole list is backed by a plain markdown file, so it is editable by hand
and survives reboots.

## What it does

- One square card per task, pinned top-left, floating above normal windows and
  on every Space.
- Card shows the task title and a short (~5 word) summary line.
- Click a card for a fast popover to edit the title, summary and detailed
  context.
- Check a task off, add a task (the dashed `+` card), or delete via right-click.
- Mildly transparent, with an adjustable transparency slider (the
  `slider.horizontal.3` button on the right of the row).
- Persists to `tasks.md`. Edits made in an external editor show up in the
  widget within ~1.5s, and edits in the widget write straight back to the file.

## Markdown format

`tasks.md` lives in the project folder. One task per `##` heading:

```markdown
# Tasks

## Ship the widget app
Get v1 building and running

Longer context in markdown, as many lines as you want.

## [x] Something already finished
Short summary line
```

- `[x]` right after `##` marks the task done. `[ ]` or nothing means open.
- The first non-empty line under a heading is the card summary.
- Everything after that is the detailed context shown in the popover.

## Configuration (AI)

The optional AI feature (auto title + preview) talks to any OpenAI-compatible
Chat Completions endpoint. Nothing gateway-specific is hardcoded; it reads a
local config file that stays on your machine:

`~/.config/taskwidgets/config.json`

```json
{
  "aiBaseURL": "https://your-openai-compatible-gateway/v1",
  "aiModel": "your-model-name",
  "aiToken": "sk-..."
}
```

Copy `config.example.json` there and fill it in. These values seed the
defaults; anything you change in the in-app Settings popover is saved to
UserDefaults and takes precedence. The config file and your `tasks.md` are
gitignored so they never get committed.

## Build & run

```bash
# Dev build + run
swift run

# Build a double-clickable .app bundle (release, no Dock icon)
./build-app.sh
open build/TaskWidgets.app
```

To launch at login: System Settings → General → Login Items → add
`build/TaskWidgets.app`.

## Architecture

- `TaskModel.swift` — the `TaskItem` value type (title, done, body, derived
  summary/context).
- `MarkdownStore.swift` — parse and serialize the task list to/from markdown.
- `TaskStore.swift` — owns the list, reads/writes the file, polls for external
  edits, stores the transparency setting.
- `Views.swift` — the card row, the card, the add card, the detail popover, the
  settings popover.
- `main.swift` — the borderless floating `NSPanel` and app lifecycle
  (`.accessory` activation, so no Dock icon).

## Requirements

- macOS 13+, Swift 6 toolchain (Command Line Tools is enough; full Xcode not
  required).
