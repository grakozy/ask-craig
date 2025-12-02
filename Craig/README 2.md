# Craig — AI answers anywhere you type on your Mac

Free & Open Source • macOS 12+ • Works with local Ollama models

> Type `/craig` (or `/ask`, `/ai`) in any app and get instant answers from your know‑it‑all assistant. No context switching.


## ✨ Landing

![Craig hero](assets/images/craig-hero.png)

<h1 align="center">
  <span style="background: linear-gradient(90deg, #c084fc, #fb7185); -webkit-background-clip: text; background-clip: text; color: transparent;">Craig</span>
</h1>

<p align="center">
  <em>AI answers anywhere you type on your Mac.</em>
</p>

<p align="center">
  <a href="#download"><img alt="Download for macOS" src="https://img.shields.io/badge/Download-macOS-7c3aed?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/grakozy/ask-craig"><img alt="View on GitHub" src="https://img.shields.io/badge/View%20on-GitHub-9333ea?style=for-the-badge&logo=github"></a>
  <a href="https://www.producthunt.com/products/craig" target="_blank"><img alt="Product Hunt" src="https://img.shields.io/badge/Product%20Hunt-Launch-ec3750?style=for-the-badge&logo=product-hunt&logoColor=white"></a>
</p>

<p align="center" style="color:#a78bfa">Requires macOS 12+ • Ollama installed • Free forever</p>


## 🖥️ How it looks

The experience mirrors this concept:

- Menu bar app, tiny and fast
- Type `/craig` anywhere (Mail, Slack, Notes, browser, IDE)
- Clean, minimal modal shows your question and an instant answer
- Press Enter to insert the response right where you were typing

> Tip: You can also use `@craig` as a live inline mention to ask without breaking flow.


## ⚡️ Three steps to AI‑powered typing

1. Type `/craig`
   - In any app—email, Slack, Notes, browser—type `/craig` followed by your question
2. Get answer
   - Local AI (via Ollama) processes your question and shows a clean modal
3. Insert
   - Hit Enter to insert the answer right where you are typing. Keep your flow.


## 🎯 Designed like Rocket. Built for AI.

- ⚡️ Lightning Fast — Optimized for speed. Great with tiny local models.
- 🔒 Private by Default — Everything runs locally. Your questions never leave your Mac.
- 🎯 Works Anywhere — System‑wide support: Gmail, Slack, Notes, iMessage, browsers.
- 🪶 Tiny (~15MB) — Lean Swift app. No Electron bloat. Starts instantly.
- 🎨 Clean & Minimal — Beautiful modal UI. Keyboard shortcuts. No clutter.
- 🆓 Free Forever — Open source. No subscriptions. No ads. No tracking.


## 🚀 Get started in 60 seconds

Just like Rocket—download, install, and you’re ready to go.

```bash
# 1) Install Ollama
brew install ollama

# 2) Pull a small, fast model (you can choose another)
ollama pull llama3.2:1b-instruct-q4_K_M

# 3) Start the Ollama server (leave this running)
ollama serve
