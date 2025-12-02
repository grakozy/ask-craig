# Craig — your know‑it‑all macOS assistant

Craig is a lightweight menu bar app that lets you ask questions anywhere you type. Trigger Craig with a slash command or mention, get an answer from a local Ollama model, and paste it back without leaving your app.

- Local‑first privacy (uses your local Ollama server)
- Keyboard‑centric UX: `/craig <question>` then Return
- Live mode: `@craig <question>` streams responses
- Preferences for trigger, model, and generation options

## Requirements
- macOS 13+
- Accessibility permission (to watch keystrokes and paste answers)
- [Ollama](https://ollama.com/) running locally

## Getting started
1. Install and launch Craig.
2. On first run, grant Accessibility permission and ensure Ollama is running.
3. Open Preferences (⌘,) to choose your trigger and model.

## Usage
- Slash trigger: Type `/craig What is a monad?` and press Return.
- Mention live mode: Type `@craig ` then your question and press Return.
- Insert (↵) pastes the answer back into the focused app.

## Preferences
- Trigger: `/craig`, `/ask`, or `/ai`
- Model: Any model installed in Ollama
- Generation: Temperature, Top‑P, Max tokens

## Troubleshooting
- “Ollama is not running”: Open Terminal and run `ollama serve`.
- No HUD or typing: Ensure Accessibility permission is enabled in System Settings → Privacy & Security → Accessibility.

## Development
- The app is split into focused files:
  - `CraigApp.swift`: entry point
  - `AppDelegate.swift`: app lifecycle, menus, windows
  - `KeyboardMonitor.swift`: keyboard event tap and command modes
  - `OllamaService.swift`: networking and streaming
  - `Views.swift`: SwiftUI views and model
  - `PreferencesView.swift`: Settings UI
- Tests live in `Tests/` and use the Swift Testing framework.

## License
MIT
