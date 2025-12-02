import SwiftUI
import Cocoa
import Carbon
import Combine

// MARK: - Main App
@main
struct CraigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - LiveCommandDelegate Protocol
protocol LiveCommandDelegate: AnyObject {
    func liveCommandDidStart(prefixDeleteCount: Int)
    func liveCommandDidUpdate(text: String)
    func liveCommandDidSubmit(text: String)
    func liveCommandDidCancel()
}

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
        
        // Setup menu
        let menu = NSMenu()
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
        // Load saved trigger phrase from UserDefaults if available
        let savedTrigger = UserDefaults.standard.string(forKey: "CraigCurrentTrigger")?.lowercased()
        if let saved = savedTrigger { keyboardMonitor.currentTrigger = saved }
        else { keyboardMonitor.currentTrigger = "/craig " }
        keyboardMonitor.start()
        
        // Insert trigger phrase submenu before Quit
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
        let modelsSubmenu = NSMenu()
        modelsMenuItem.submenu = modelsSubmenu
        menu.addItem(modelsMenuItem)
        menu.addItem(NSMenuItem(title: "Refresh Models", action: #selector(refreshModels), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        self.statusItem.menu = menu
        // Populate models list
        refreshModels()
        
        menu.addItem(NSMenuItem(title: "Quit Craig", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Check Ollama on startup
        checkOllamaOnStartup()
    }
    
    @objc func refreshModels() {
        ollamaService.listModels { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, let menu = self.statusItem.menu else { return }
                // Find the Model submenu we previously inserted
                guard let modelsItem = menu.items.first(where: { $0.title == "Model" }), let submenu = modelsItem.submenu else { return }
                submenu.removeAllItems()
                switch result {
                case .success(let names):
                    // Choose a tiny fast default if current selection is missing
                    let preferredDefaults = [
                        "llama3.2:1b-instruct-q4_K_M",
                        "qwen2.5:0.5b-instruct-q4_K_M",
                        "phi3:mini",
                        "tinyllama:latest"
                    ]
                    if !names.contains(self.ollamaService.selectedModel) {
                        if let pick = preferredDefaults.first(where: { names.contains($0) }) ?? names.first {
                            self.ollamaService.setSelectedModel(pick)
                        }
                    }
                    for name in names {
                        let item = NSMenuItem(title: name, action: #selector(self.selectModel(_:)), keyEquivalent: "")
                        item.target = self
                        item.state = (name == self.ollamaService.selectedModel) ? .on : .off
                        submenu.addItem(item)
                    }
                    if names.isEmpty {
                        let empty = NSMenuItem(title: "No models found", action: nil, keyEquivalent: "")
                        empty.isEnabled = false
                        submenu.addItem(empty)
                    }
                case .failure(let error):
                    let errItem = NSMenuItem(title: "Error: \(error.localizedDescription)", action: nil, keyEquivalent: "")
                    errItem.isEnabled = false
                    submenu.addItem(errItem)
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
        UserDefaults.standard.synchronize()
    }
    
    @objc func statusItemClicked() {
        statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Craig v1.0"
        alert.informativeText = "Your know-it-all personal assistant.\n\nType /craig anywhere to ask questions."
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
            if !isRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.checkOllama()
                }
            }
        }
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func handleSlashCraig(text: String) {
        DispatchQueue.main.async {
            self.showModal(with: text)
        }
    }
    
    func showModal(with question: String) {
        DispatchQueue.main.async {
            // Close existing modal if any
            self.modalWindow?.close()

            let modal = CraigModalView(question: question, ollamaService: self.ollamaService) { [weak self] response in
                self?.modalWindow?.close()
                self?.insertText(response)
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

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.modalWindow = window
        }
    }
    
    func insertText(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Simulate Cmd+V to paste (after ensuring focus returned to the previous app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            let source = CGEventSource(stateID: .hidSystemState)
            
            // Key down Cmd
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            cmdDown?.flags = .maskCommand
            
            // Press V
            let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            vDown?.flags = .maskCommand
            let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            vUp?.flags = .maskCommand
            
            // Key up Cmd
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            
            cmdDown?.post(tap: .cghidEventTap)
            vDown?.post(tap: .cghidEventTap)
            vUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
        }
    }
    
    func deleteCharacters(count: Int) {
        guard count > 0 else { return }
        DispatchQueue.main.async {
            for _ in 0..<count {
                let source = CGEventSource(stateID: .hidSystemState)
                let deleteDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
                let deleteUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
                deleteDown?.post(tap: .cghidEventTap)
                deleteUp?.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - KeyboardMonitorDelegate
    func keyboardMonitor(didUpdatePreview preview: String, trigger: String) {
        showHUD(trigger: trigger, preview: preview)
    }

    func keyboardMonitorDidEnterCommandMode(trigger: String) {
        showHUD(trigger: trigger, preview: "")
    }

    func keyboardMonitorDidExitCommandMode() {
        hideHUD()
    }

    private func showHUD(trigger: String, preview: String) {
        let content = CommandHUDView(trigger: trigger, preview: preview)
        if let hudWindow = hudWindow {
            if let hosting = hudWindow.contentViewController as? NSHostingController<CommandHUDView> {
                hosting.rootView = content
            }
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

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
        hudWindow = window
    }

    private func hideHUD() {
        hudWindow?.orderOut(nil)
    }
    
    // MARK: - LiveCommandDelegate
    func liveCommandDidStart(prefixDeleteCount: Int) {
        // Remove the @craig mention (and trailing delimiter) from the focused app so we can insert the answer in its place
        deleteCharacters(count: prefixDeleteCount)
        let model = LiveCommandModel()
        self.liveModel = model
        showLiveModal(model: model)
    }
    
    func liveCommandDidUpdate(text: String) {
        liveModel?.question = text
    }
    
    func liveCommandDidSubmit(text: String) {
        liveModel?.submitTick += 1
    }
    
    func liveCommandDidCancel() {
        modalWindow?.close()
        liveModalController = nil
        liveModel = nil
    }
    
    private func showLiveModal(model: LiveCommandModel) {
        // Close any existing modal
        modalWindow?.close()

        let view = CraigLiveModalView(ollamaService: ollamaService, model: model) { [weak self] response in
            self?.modalWindow?.close()
            self?.liveModalController = nil
            self?.liveModel = nil
            self?.insertText(response)
        } onClose: { [weak self] in
            self?.modalWindow?.close()
            self?.liveModalController = nil
            self?.liveModel = nil
        }
        let hosting = NSHostingController(rootView: view)
        liveModalController = hosting
        let window = NSWindow(contentViewController: hosting)
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

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        modalWindow = window
    }
}

// MARK: - KeyboardMonitorDelegate Protocol
protocol KeyboardMonitorDelegate: AnyObject {
    func keyboardMonitor(didUpdatePreview preview: String, trigger: String)
    func keyboardMonitorDidEnterCommandMode(trigger: String)
    func keyboardMonitorDidExitCommandMode()
}

// MARK: - Keyboard Monitor
class KeyboardMonitor {
    weak var delegate: KeyboardMonitorDelegate?
    weak var liveDelegate: LiveCommandDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private let triggerPattern = "/craig "
    private var onTrigger: (String) -> Void

    // Quote handling: support straight quotes, smart quotes, and backticks
    private let openingQuotes: Set<Character> = ["\"", "“", "‘", "`"]
    private let closingMap: [Character: Character] = [
        "\"": "\"",
        "“": "\"",
        "‘": "'",
        "`": "`"
    ]

    private func normalizeQuotes(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.count)
        for ch in s {
            if ch == "“" || ch == "”" { result.append("\"") }
            else if ch == "‘" || ch == "’" { result.append("'") }
            else { result.append(ch) }
        }
        return result
    }

    init(onTrigger: @escaping (String) -> Void) {
        self.onTrigger = onTrigger
    }
    
    var currentTrigger: String = "/craig " {
        didSet {
            currentTrigger = currentTrigger.lowercased()
            UserDefaults.standard.set(currentTrigger, forKey: "CraigCurrentTrigger")
        }
    }
    let supportedTriggers: [String] = ["/craig ", "/ask ", "/ai "]
    
    private var inLiveMode = false
    private var liveBuffer = ""
    private let mentionTrigger = "@craig"
    
    func start() {
        let eventMask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap - need Accessibility permissions!")
            self.showAccessibilityAlert()
            return
        }
        
        print("✅ Keyboard monitor started successfully!")
        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    func showAccessibilityAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Craig needs Accessibility permissions"
            alert.informativeText = "1. Open System Settings\n2. Go to Privacy & Security → Accessibility\n3. Toggle Craig ON\n4. Restart Craig"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Quit")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }
        
        if let nsEvent = NSEvent(cgEvent: event),
           let characters = nsEvent.characters {
            
            // Only consider visible, single-character input from the keyboard. Ignore function keys etc.
            let chars = characters
            print("🔑 Key pressed: \(chars) | Buffer: \(buffer)")
            
            // Tab-complete @craig when typing its prefix
            if !inLiveMode && nsEvent.keyCode == 48 { // Tab key
                let lower = buffer.lowercased()
                // Find the longest suffix of buffer that is a prefix of mentionTrigger
                let candidates = ["@craig", "@crai", "@cra", "@cr", "@c", "@"]
                if let match = candidates.first(where: { lower.hasSuffix($0) }) {
                    let completion = "@craig"
                    if match != completion {
                        let remaining = String(completion.dropFirst(match.count)) + " "
                        // Type remaining characters into the focused app and update buffer
                        typeText(remaining)
                        buffer += remaining
                        // Show HUD suggestion state
                        delegate?.keyboardMonitorDidEnterCommandMode(trigger: "@craig")
                        delegate?.keyboardMonitor(didUpdatePreview: "", trigger: "@craig")
                        return nil // consume Tab
                    } else {
                        // Already complete; add a space if not present
                        if !lower.hasSuffix("@craig ") { typeText(" "); buffer += " " }
                        return nil
                    }
                }
            }
            
            let lowerBuffer = buffer.lowercased()
            // Enter live mode when we see @craig followed by space/colon/comma
            if !inLiveMode {
                var deleteCount: Int? = nil
                if lowerBuffer.hasSuffix(mentionTrigger + " ") { deleteCount = mentionTrigger.count + 1 }
                else if lowerBuffer.hasSuffix(mentionTrigger + ":") { deleteCount = mentionTrigger.count + 1 }
                else if lowerBuffer.hasSuffix(mentionTrigger + ",") { deleteCount = mentionTrigger.count + 1 }
                else if lowerBuffer.hasSuffix(mentionTrigger) { deleteCount = mentionTrigger.count }
                if let count = deleteCount {
                    inLiveMode = true
                    liveBuffer = ""
                    liveDelegate?.liveCommandDidStart(prefixDeleteCount: count)
                    // Do not pass the trigger keystrokes further (consume now)
                }
            }
            
            if inLiveMode {
                // Handle control keys in live mode
                // Enter -> submit
                if nsEvent.keyCode == 36 || nsEvent.keyCode == 76 {
                    liveDelegate?.liveCommandDidSubmit(text: liveBuffer)
                    inLiveMode = false
                    liveBuffer = ""
                    buffer = "" // reset typed buffer
                    return nil
                }
                // Escape -> cancel
                if nsEvent.keyCode == 53 { // esc
                    liveDelegate?.liveCommandDidCancel()
                    inLiveMode = false
                    liveBuffer = ""
                    buffer = ""
                    return nil
                }
                // Backspace
                if nsEvent.keyCode == 51 {
                    if !liveBuffer.isEmpty { liveBuffer.removeLast() }
                    liveDelegate?.liveCommandDidUpdate(text: liveBuffer)
                    return nil
                }
                // Append printable characters; ignore modifiers
                if let chars = nsEvent.characters, let scalar = chars.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) {
                    liveBuffer.append(chars)
                    liveDelegate?.liveCommandDidUpdate(text: liveBuffer)
                    return nil
                }
            }
            
            // Check for Enter/Return key
            if nsEvent.keyCode == 36 || nsEvent.keyCode == 76 {
                let lower = buffer.lowercased()
                if lower.hasPrefix(triggerPattern) {
                    var remainder = String(buffer.dropFirst(triggerPattern.count))
                    remainder = normalizeQuotes(remainder).trimmingCharacters(in: .whitespacesAndNewlines)

                    var extracted = ""
                    if let first = remainder.first, openingQuotes.contains(first) {
                        let closing = closingMap[first] ?? first
                        remainder.removeFirst()
                        if let endIndex = remainder.firstIndex(of: closing) {
                            extracted = String(remainder[..<endIndex])
                        } else {
                            extracted = remainder
                        }
                    } else {
                        extracted = remainder
                    }
                    extracted = extracted.trimmingCharacters(in: .whitespacesAndNewlines)

                    if !extracted.isEmpty {
                        deleteBuffer()
                        onTrigger(extracted)
                        buffer = ""
                        delegate?.keyboardMonitorDidExitCommandMode()
                        return nil
                    }
                }
                buffer = ""
                delegate?.keyboardMonitorDidExitCommandMode()
                return Unmanaged.passUnretained(event)
            }

            // Backspace
            if nsEvent.keyCode == 51 {
                if !buffer.isEmpty { buffer.removeLast() }
                let lower = buffer.lowercased()
                if lower.hasPrefix(triggerPattern) {
                    let preview = String(buffer.dropFirst(triggerPattern.count))
                    delegate?.keyboardMonitor(didUpdatePreview: normalizeQuotes(preview), trigger: String(triggerPattern.dropLast()))
                } else {
                    delegate?.keyboardMonitorDidExitCommandMode()
                }
                return Unmanaged.passUnretained(event)
            }

            // Append characters (normalize quotes)
            let normalized = normalizeQuotes(characters)
            buffer += normalized

            // If user is typing the @craig mention, hint via HUD
            let suffixes = ["@", "@c", "@cr", "@cra", "@crai", "@craig"]
            if suffixes.contains(where: { buffer.lowercased().hasSuffix($0) }) {
                delegate?.keyboardMonitorDidEnterCommandMode(trigger: "@craig")
                delegate?.keyboardMonitor(didUpdatePreview: "Press Tab to autocomplete", trigger: "@craig")
            }

            // Size guard
            if buffer.count > 500 { buffer = String(buffer.suffix(500)) }

            let lower = buffer.lowercased()
            if lower.hasPrefix(triggerPattern) {
                // Enter command mode if just matched the trigger
                delegate?.keyboardMonitorDidEnterCommandMode(trigger: String(triggerPattern.dropLast()))
                let preview = String(buffer.dropFirst(triggerPattern.count))
                delegate?.keyboardMonitor(didUpdatePreview: normalizeQuotes(preview), trigger: String(triggerPattern.dropLast()))
            } else if !triggerPattern.hasPrefix(lower) && lower.count >= triggerPattern.count {
                // Pattern broken, exit command mode
                delegate?.keyboardMonitorDidExitCommandMode()
                buffer = ""
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    func deleteBuffer() {
        let deleteCount = buffer.count
        print("🗑️ Deleting \(deleteCount) characters")
        DispatchQueue.main.async {
            for _ in 0..<deleteCount {
                let source = CGEventSource(stateID: .hidSystemState)
                let deleteDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
                let deleteUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
                deleteDown?.post(tap: .cghidEventTap)
                deleteUp?.post(tap: .cghidEventTap)
            }
        }
    }
    
    private func typeText(_ text: String) {
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)
            for ch in text {
                // Use UniChar event to better support letters regardless of layout
                let s = String(ch) as NSString
                let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                eventDown?.keyboardSetUnicodeString(stringLength: s.length, unicodeString: s.utf16String)
                let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                eventUp?.keyboardSetUnicodeString(stringLength: s.length, unicodeString: s.utf16String)
                eventDown?.post(tap: .cghidEventTap)
                eventUp?.post(tap: .cghidEventTap)
            }
        }
    }
    
    deinit {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
    }
}

// MARK: - Ollama Service
class OllamaService {
    private let session: URLSession

    // Persisted selected model
    private(set) var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "CraigSelectedModel") }
    }

    private let maxTokens: Int = 256
    private let temperature: Double = 0.2
    private let topP: Double = 0.9
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        // Load persisted selection or a tiny fast default commonly available
        self.selectedModel = UserDefaults.standard.string(forKey: "CraigSelectedModel") ?? "llama3.2:1b-instruct-q4_K_M"
    }
    
    func checkStatus(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let task = session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                completion(httpResponse.statusCode == 200)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
    
    struct OllamaTag: Decodable { let name: String }
    struct TagsResponse: Decodable { let models: [OllamaTag]? }

    func listModels(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data else { completion(.failure(NSError(domain: "No data", code: -1))); return }
            // Try to decode known schema; if it fails, try to parse minimal JSON
            if let decoded = try? JSONDecoder().decode(TagsResponse.self, from: data), let models = decoded.models?.map({ $0.name }) {
                completion(.success(models))
                return
            }
            // Fallback to permissive JSON parsing
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {
                    let names = models.compactMap { $0["name"] as? String }
                    completion(.success(names))
                } else {
                    completion(.failure(NSError(domain: "Invalid response", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected tags schema"])) )
                }
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    func setSelectedModel(_ name: String) { self.selectedModel = name }
    
    func ask(question: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:11434/api/generate") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        let body: [String: Any] = [
            "model": selectedModel,
            "prompt": question,
            "stream": false,
            "options": [
                "temperature": temperature,
                "top_p": topP,
                "num_predict": maxTokens
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let response = json["response"] as? String {
                        completion(.success(response))
                        return
                    }
                    if let errorMsg = json["error"] as? String {
                        completion(.failure(NSError(domain: "Ollama", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
                        return
                    }
                }
                completion(.failure(NSError(domain: "Invalid response", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unexpected generate schema"])) )
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
}

// MARK: - Modal View
struct CraigModalView: View {
    let question: String
    let ollamaService: OllamaService
    let onInsert: (String) -> Void
    let onClose: () -> Void
    
    @State private var response: String = ""
    @State private var isLoading: Bool = true
    @State private var error: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Craig")
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("Esc to close")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button(action: { onClose() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                    .keyboardShortcut(.escape, modifiers: [])
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your question:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(question)
                        .padding()
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    
                    Text("Response:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Craig is thinking...")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                    } else if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    } else {
                        Text(response)
                            .padding()
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            // Buttons
            if !isLoading && error == nil {
                HStack(spacing: 12) {
                    Button(action: {
                        onInsert(response)
                    }) {
                        Text("Insert ↵")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [])
                    
                    Button(action: {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(response, forType: .string)
                    }) {
                        Text("Copy")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            
            // Hidden cancel shortcut to ensure Command+. always closes
            Button(action: { onClose() }) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        .frame(width: 500, height: 300)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onAppear {
            fetchResponse()
        }
        .onExitCommand(perform: {
            onClose()
        })
    }
    
    func fetchResponse() {
        ollamaService.ask(question: question) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let text):
                    response = text
                case .failure(let err):
                    error = "Error: \(err.localizedDescription)\n\nMake sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve"
                }
            }
        }
    }
}

// MARK: - Command HUD View
struct CommandHUDView: View {
    let trigger: String
    let preview: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text(trigger)
                .font(.caption).bold()
                .foregroundStyle(.purple)
            Text(preview.isEmpty ? "" : preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 6)
    }
}

// Insert new LiveCommandModel observable object here, after CommandHUDView and before CraigLiveModalView
final class LiveCommandModel: ObservableObject {
    @Published var question: String = ""
    @Published var submitTick: Int = 0
    @Published var lastResponse: String = ""
    @Published var lastError: String? = nil
}

// MARK: - CraigLiveModalView
struct CraigLiveModalView: View {
    let ollamaService: OllamaService
    @ObservedObject var model: LiveCommandModel
    let onInsert: (String) -> Void
    let onClose: () -> Void

    @State private var response: String = ""
    @State private var isLoading: Bool = false
    @State private var error: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles").foregroundColor(.purple)
                Text("Craig").font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("Esc to close").font(.caption).foregroundColor(.secondary)
                    Button(action: { onClose() }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding()
            .background(Color.purple.opacity(0.1))

            // Chat content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // User bubble
                        if !model.question.isEmpty {
                            HStack {
                                Spacer(minLength: 40)
                                Text(model.question)
                                    .padding(10)
                                    .background(Color.accentColor.opacity(0.15))
                                    .foregroundColor(.primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .id("user")
                        } else {
                            HStack {
                                Spacer(minLength: 40)
                                Text("Start typing…")
                                    .foregroundColor(.secondary)
                                    .padding(10)
                                    .background(Color.accentColor.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .id("user")
                        }

                        // Assistant bubble / states
                        if isLoading {
                            HStack(alignment: .top) {
                                Text("")
                                VStack(alignment: .leading) {
                                    HStack { ProgressView().scaleEffect(0.8); Text("Craig is thinking…").foregroundColor(.secondary) }
                                }
                                Spacer()
                            }
                            .id("assistant")
                        } else if let error = error {
                            HStack(alignment: .top) {
                                Text("")
                                VStack(alignment: .leading) {
                                    Text(error).foregroundColor(.red)
                                        .padding(10)
                                        .background(Color.red.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                Spacer()
                            }
                            .id("assistant")
                        } else if !response.isEmpty {
                            HStack(alignment: .top) {
                                Text("")
                                VStack(alignment: .leading) {
                                    Text(response)
                                        .padding(10)
                                        .background(Color.white.opacity(0.05))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                Spacer()
                            }
                            .id("assistant")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .onChange(of: response) { _ in withAnimation { proxy.scrollTo("assistant", anchor: .bottom) } }
                .onChange(of: isLoading) { _ in withAnimation { proxy.scrollTo("assistant", anchor: .bottom) } }
                .onChange(of: model.question) { _ in withAnimation { proxy.scrollTo("user", anchor: .bottom) } }
            }

            // Actions
            HStack(spacing: 12) {
                Button(action: { onInsert(response) }) {
                    Text("Insert ↵")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background((!isLoading && error == nil && !response.isEmpty) ? Color.purple : Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(isLoading || !(error == nil && !response.isEmpty))

                Button(action: {
                    let pb = NSPasteboard.general; pb.clearContents(); pb.setString(response, forType: .string)
                }) {
                    Text("Copy")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(response.isEmpty)
            }
            .padding()
        }
        .frame(width: 560, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
        .onChange(of: model.submitTick) { _ in
            submit()
        }
    }

    func submit() {
        let q = model.question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        response = ""
        error = nil
        ollamaService.ask(question: q) { result in
            DispatchQueue.main.async {
                isLoading = false
                switch result {
                case .success(let text):
                    response = text
                    model.lastResponse = text
                    model.lastError = nil
                case .failure(let err):
                    let msg = "Error: \(err.localizedDescription)\n\nMake sure Ollama is running:\n1. Open Terminal\n2. Run: ollama serve"
                    error = msg
                    model.lastError = msg
                }
            }
        }
    }
}

