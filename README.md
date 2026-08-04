# Sanity

A small, fast, native macOS desktop widget for tasks. Square sticky-note cards
pin to the top of your desktop, each one a task with a title and a short
preview. Click a card for a fast centered editor with a connector line back to
the card. Everything is backed by a plain markdown file, so it is editable by
hand and survives reboots.

Optionally, an OpenAI-compatible model can title and summarize each task for
you: it picks an emoji category (Fix, Monitor, Notify, Triage, Mitigate,
Review) and writes a short preview.

## Features

- One square card per task, pinned to the desktop, on every Space.
- Fast centered editor with a connector line to the source card.
- Drag cards left/right to reorder; lock the widget in place.
- Adjustable size (with a percent field) and transparency.
- Menu bar item: new task, center, open the file, quit.
- Markdown-backed and reloads on external edits.
- Optional AI: emoji title + short preview, auto-run on new tasks and re-run
  when you edit a task.

## Install

Download `Sanity.dmg` from the latest release, open it, and drag **Sanity**
into Applications. Launch it from Spotlight or Applications.

It runs as a menu bar app (no Dock icon). The first launch seeds a few example
tasks.

## Configuration (optional AI)

The AI feature talks to any OpenAI-compatible Chat Completions endpoint.
Nothing is hardcoded; it reads a local config file:

`~/.config/sanity/config.json`

```json
{
  "aiBaseURL": "https://your-openai-compatible-gateway/v1",
  "aiModel": "your-model-name",
  "aiToken": "sk-..."
}
```

Copy `config.example.json` there and fill it in, then turn on **Enable AI** in
the settings popover. Values you change in-app take precedence. Your tasks
(`~/.config/sanity/tasks.md`) and this config file stay on your machine.

## Task file format

One task per `##` heading:

```markdown
# Tasks

## 🔧 Fix
Update the Terraform module for the cache key

Longer notes go here, as many lines as you want.
```

The first non-empty line under a heading is the card preview; the rest is the
detailed context. `## [x] Title` marks a task done.

## Build from source

Requires macOS 13+ and a Swift 6 toolchain (Xcode command line tools is
enough).

```bash
swift run              # dev build + run
./build-app.sh         # build Sanity.app into build/
./make-dmg.sh          # build the app and package build/Sanity.dmg
```

## License

MIT. See [LICENSE](LICENSE).
