# Craig — AI answers anywhere you type on macOS

Craig is a lightweight, privacy‑first menu bar assistant that answers questions anywhere you type. Trigger Craig with a slash command or mention, get an answer from a local Ollama model, and paste it back without breaking flow.

- ⚡️ Keyboard‑first: Type `/craig <question>` and press Return
- ✨ Live mode: Type `@craig ` then your question and press Return to stream answers
- 🔒 Private by default: Runs locally with your own Ollama models
- 🎛️ Preferences: Choose trigger phrase, model, and generation options
- 🖥️ Tiny Swift app: Native macOS UI, no Electron

> Status: Open source and free. This is my first public project — feedback welcome!

## Demo

- Slash command flow: `/craig how do I write a for loop in Swift?` → modal appears → Insert pastes back into the focused app
- Mention live mode: `@craig ` + your question → live modal streams the answer → Esc cancels; Insert pastes back

(Screenshots/GIFs coming soon.)

## Requirements
- macOS 13+
- Accessibility permission (to watch keystrokes and paste answers)
- [Ollama](https://ollama.com/) running locally

## Quick start

1) Install Ollama (and pull a small, fast model)
