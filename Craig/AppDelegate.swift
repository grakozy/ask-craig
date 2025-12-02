import Cocoa
import SwiftUI

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, KeyboardMonitorDelegate, LiveCommandDelegate {
    var statusItem: NSStatusItem!
    var keyboardMonitor: KeyboardMonitor!
    var modalWindow: NSWindow?
    var liveModalController: NSHostingController<CraigLiveModalView>?
    var liveModel: LiveCommandModel?
    var hudWindow: NSWindow?
    var ollamaService = OllamaService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Craig")
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())

        // Setup menu
        menu.addItem(NSMenuItem(title: "About Craig", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check Ollama Status", action: #selector(checkOllama), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        // Start keyboard monitoring
        keyboardMonitor = KeyboardMonitor { [weak self] text in
            self?.handleSlashCraig(text: text)
        }
        keyboardMonitor.delegate = self
        keyboardMonitor.liveDelegate = self
        let savedTrigger = UserDefaults.standard.string(forKey: "CraigCurrentTrigger")?.lowercased()
        if let saved = savedTrigger { keyboardMonitor.currentTrigger = saved } else { keyboardMonitor.currentTrigger = "/craig " }
        keyboardMonitor.start()

        NotificationCenter.default.addObserver(forName: Notification.Name("CraigTriggerChanged"), object: nil, queue: .main) { [weak self] note in
            if let trig = note.userInfo?["trigger"] as? String {
                self?.keyboardMonitor?.currentTrigger = trig
                UserDefaults.standard.set(trig, forKey: "CraigCurrentTrigger")
            }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("CraigSelectedModelChanged"), object: nil, queue: .main) { [weak self] note in
            if let model = note.userInfo?["model"] as? String { self?.ollamaService.setSelectedModel(model) }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("CraigGenOptionsChanged"), object: nil, queue: .main) { [weak self] note in
            let temp = note.userInfo?["temperature"] as? Double
            let topP = note.userInfo?["topP"] as? Double
            let maxToks = note.userInfo?["maxTokens"] as? Int
            self?.ollamaService.setOptions(maxTokens: maxToks, temperature: temp, topP: topP)
        }

        showFirstRunOnboardingIfNeeded()

        // Trigger submenu
        let triggersMenuItem = NSMenuItem(title: "Trigger Phrase", action: nil, keyEquivalent: "")
        let triggersSubmenu = NSMenu()
        let triggerOptions = ["/craig ", "/ask ", "/ai "]
        let current = UserDefaults.standard.string(forKey: "CraigCurrentTrigger")?.lowercased() ?? keyboardMonitor?.currentTrigger ?? "/craig "
        for option in triggerOptions {
            let item = NSMenuItem(title: option, action: #selector(setTrigger(_:)), keyEquivalent: "")
            item.target = self
            item.state = (current == option) ? .on : .off
            triggersSubmenu.addItem(item)
        }
        triggersMenuItem.submenu = triggersSubmenu
        menu.addItem(triggersMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Models submenu
        let modelsMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelsSubmenu = NSMenu(); modelsMenuItem.submenu = modelsSubmenu
        menu.addItem(modelsMenuItem)
        menu.addItem(NSMenuItem(title: "Refresh Models", action: #selector(refreshModels), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        self.statusItem.menu = menu
        refreshModels()

        menu.addItem(NSMenuItem(title: "Quit Craig", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        checkOllamaOnStartup()
    }

    @objc func openPreferences() { NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }

    private func showFirstRunOnboardingIfNeeded() {
        let key = "CraigFirstRunCompleted"
        if !UserDefaults.standard.bool(forKey: key) {
            let alert = NSAlert()
            alert.messageText = "Welcome to Craig"
            alert.informativeText = "Craig helps you get answers anywhere you type.\n\nSetup steps:\n• Grant Accessibility permission so Craig can watch keystrokes and paste answers.\n• Ensure Ollama is running (open Terminal and run: ollama serve).\n\nYou can change the trigger phrase and model in Preferences."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Accessibility Settings")
            alert.addButton(withTitle: "Continue")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    @objc func refreshModels() {
        ollamaService.listModels { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let menu = self.statusItem.menu else { return }
                guard let modelsItem = menu.items.first(where: { $0.title == "Model" }), let submenu = modelsItem.submenu else { return }
                submenu.removeAllItems()
                switch result {
                case .success(let names):
                    let preferredDefaults = ["llama3.2:1b-instruct-q4_K_M", "qwen2.5:0.5b-instruct-q4_K_M", "phi3:mini", "tinyllama:latest"]
                    if !names.contains(self.ollamaService.selectedModel) {
                        if let pick = preferredDefaults.first(where: { names.contains($0) }) ?? names.first { self.ollamaService.setSelectedModel(pick) }
                    }
                    for name in names {
                        let item = NSMenuItem(title: name, action: #selector(self.selectModel(_:)), keyEquivalent: "")
                        item.target = self; item.state = (name == self.ollamaService.selectedModel) ? .on : .off
                        submenu.addItem(item)
                    }
                    if names.isEmpty { let empty = NSMenuItem(title: "No models found", action: nil, keyEquivalent: ""); empty.isEnabled = false; submenu.addItem(empty) }
                case .failure(let error):
                    let errItem = NSMenuItem(title: "Error: \(error.localizedDescription)", action: nil, keyEquivalent: ""); errItem.isEnabled = false; submenu.addItem(errItem)
                }
            }
        }
    }

    @objc func selectModel(_ sender: NSMenuItem) {
        guard let menu = sender.menu else { return }
        for item in menu.items { item.state = .off }
        sender.state = .on
        ollamaService.setSelectedModel(sender.title)
    }

    @objc func setTrigger(_ sender: NSMenuItem) {
        guard let submenu = sender.menu else { return }
        for item in submenu.items { item.state = .off }
        sender.state = .on
        keyboardMonitor?.currentTrigger = sender.title.lowercased()
        UserDefaults.standard.set(sender.title.lowercased(), forKey: "CraigCurrentTrigger")
    }

    @objc func statusItemClicked() { statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }

    @objc func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let alert = NSAlert()
        alert.messageText = "Craig v\(version)\(build != nil ? " (\(build!))" : "")"
        alert.informativeText = "Your know-it-all personal assistant.\n\nType \(UserDefaults.standard.string(forKey: "CraigCurrentTrigger") ?? "/craig ") anywhere to ask questions."
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func checkOllama() {
        ollamaService.checkStatus { isRunning in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if isRunning {
                    alert.messageText = "Ollama is running ✓"
                    alert.informativeText = "Craig is ready to answer your questions!"
                    alert.alertStyle = .informational
                } else {
                    alert.messageText = "Ollama is not running ✗"
                    alert.informativeText = "Please start Ollama:\n\n1. Open Terminal\n2. Run: ollama serve"
                    alert.alertStyle = .warning
                }
                alert.runModal()
            }
        }
    }

    func checkOllamaOnStartup() {
        ollamaService.checkStatus { isRunning in
            if !isRunning { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.checkOllama() } }
        }
    }

    @objc func quitApp() { NSApplication.shared.terminate(nil) }

    func handleSlashCraig(text: String) { DispatchQueue.main.async { self.showModal(with: text) } }

    func showModal(with question: String) {
        DispatchQueue.main.async {
            self.modalWindow?.close()
            let modal = CraigModalView(question: question, ollamaService: self.ollamaService) { [weak self] response in
                self?.modalWindow?.close(); self?.insertText(response)
            } onClose: { [weak self] in
                self?.modalWindow?.close()
            }
            let hostingController = NSHostingController(rootView: modal)
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.borderless, .fullSizeContentView]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.level = .floating
            window.isMovableByWindowBackground = true

            if let screen = NSScreen.main {
                let screenFrame = screen.frame
                let windowSize = NSSize(width: 500, height: 300)
                let x = (screenFrame.width - windowSize.width) / 2
                let y = (screenFrame.height - windowSize.height) / 2
                window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: windowSize), display: true)
            }

            // Animate appearance
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 1
            }
            self.modalWindow = window
        }
    }

    func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let source = CGEventSource(stateID: .hidSystemState)
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true); cmdDown?.flags = .maskCommand
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true); vDown?.flags = .maskCommand
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false); vUp?.flags = .maskCommand
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            cmdDown?.post(tap: .cghidEventTap); vDown?.post(tap: .cghidEventTap); vUp?.post(tap: .cghidEventTap); cmdUp?.post(tap: .cghidEventTap)
        }
    }

    func deleteCharacters(count: Int) {
        guard count > 0 else { return }
        DispatchQueue.main.async {
            for _ in 0..<count {
                let source = CGEventSource(stateID: .hidSystemState)
                let deleteDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
                let deleteUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
                deleteDown?.post(tap: .cghidEventTap); deleteUp?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - KeyboardMonitorDelegate
    func keyboardMonitor(didUpdatePreview preview: String, trigger: String) { showHUD(trigger: trigger, preview: preview) }
    func keyboardMonitorDidEnterCommandMode(trigger: String) { showHUD(trigger: trigger, preview: "") }
    func keyboardMonitorDidExitCommandMode() { hideHUD() }

    private func showHUD(trigger: String, preview: String) {
        let content = CommandHUDView(trigger: trigger, preview: preview)
        if let hudWindow = hudWindow {
            if let hosting = hudWindow.contentViewController as? NSHostingController<CommandHUDView> { hosting.rootView = content }
            hudWindow.orderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hasShadow = false

        if let screen = NSScreen.main {
            let size = NSSize(width: 320, height: 64)
            let x = (screen.frame.width - size.width) / 2
            let y = screen.frame.height - size.height - 120
            window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
        }

        // Fade-in animation
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            window.animator().alphaValue = 1
        }
        hudWindow = window
    }

    private func hideHUD() { hudWindow?.orderOut(nil) }

    // MARK: - LiveCommandDelegate
    func liveCommandDidStart(prefixDeleteCount: Int) {
        deleteCharacters(count: prefixDeleteCount)
        let model = LiveCommandModel(); self.liveModel = model; showLiveModal(model: model)
    }
    func liveCommandDidUpdate(text: String) { liveModel?.question = text }
    func liveCommandDidSubmit(text: String) { liveModel?.submitTick += 1 }
    func liveCommandDidCancel() { modalWindow?.close(); liveModalController = nil; liveModel = nil }

    private func showLiveModal(model: LiveCommandModel) {
        modalWindow?.close()
        let view = CraigLiveModalView(ollamaService: ollamaService, model: model) { [weak self] response in
            self?.modalWindow?.close(); self?.liveModalController = nil; self?.liveModel = nil; self?.insertText(response)
        } onClose: { [weak self] in
            self?.modalWindow?.close(); self?.liveModalController = nil; self?.liveModel = nil
        }
        let hosting = NSHostingController(rootView: view); liveModalController = hosting
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless, .fullSizeContentView]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let windowSize = NSSize(width: 560, height: 420)
            let x = (screenFrame.width - windowSize.width) / 2
            let y = (screenFrame.height - windowSize.height) / 2
            window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: windowSize), display: true)
        }
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            window.animator().alphaValue = 1
        }
        modalWindow = window
    }
}
