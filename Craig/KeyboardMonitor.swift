import Cocoa

// MARK: - KeyboardMonitorDelegate Protocol
protocol KeyboardMonitorDelegate: AnyObject {
    func keyboardMonitor(didUpdatePreview preview: String, trigger: String)
    func keyboardMonitorDidEnterCommandMode(trigger: String)
    func keyboardMonitorDidExitCommandMode()
}

// MARK: - LiveCommandDelegate Protocol
protocol LiveCommandDelegate: AnyObject {
    func liveCommandDidStart(prefixDeleteCount: Int)
    func liveCommandDidUpdate(text: String)
    func liveCommandDidSubmit(text: String)
    func liveCommandDidCancel()
}

// MARK: - Keyboard Monitor
class KeyboardMonitor {
    weak var delegate: KeyboardMonitorDelegate?
    weak var liveDelegate: LiveCommandDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
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
        var result = ""; result.reserveCapacity(s.count)
        for ch in s {
            if ch == "“" || ch == "”" { result.append("\"") }
            else if ch == "‘" || ch == "’" { result.append("'") }
            else { result.append(ch) }
        }
        return result
    }

    init(onTrigger: @escaping (String) -> Void) { self.onTrigger = onTrigger }

    var currentTrigger: String = "/craig " {
        didSet { UserDefaults.standard.set(currentTrigger.lowercased(), forKey: "CraigCurrentTrigger") }
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

    private func showAccessibilityAlert() {
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

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if let nsEvent = NSEvent(cgEvent: event), let characters = nsEvent.characters {
            #if DEBUG
            print("🔑 Key pressed: \(characters) | Buffer: \(buffer)")
            #endif

            // Tab-complete @craig when typing its prefix
            if !inLiveMode && nsEvent.keyCode == 48 {
                let lower = buffer.lowercased()
                let candidates = ["@craig", "@crai", "@cra", "@cr", "@c", "@"]
                if let match = candidates.first(where: { lower.hasSuffix($0) }) {
                    let completion = "@craig"
                    if match != completion {
                        let remaining = String(completion.dropFirst(match.count)) + " "
                        typeText(remaining)
                        buffer += remaining
                        delegate?.keyboardMonitorDidEnterCommandMode(trigger: "@craig")
                        delegate?.keyboardMonitor(didUpdatePreview: "", trigger: "@craig")
                        return nil
                    } else {
                        if !lower.hasSuffix("@craig ") { typeText(" "); buffer += " " }
                        return nil
                    }
                }
            }

            let lowerBuffer = buffer.lowercased()
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
                }
            }

            if inLiveMode {
                if nsEvent.keyCode == 36 || nsEvent.keyCode == 76 {
                    liveDelegate?.liveCommandDidSubmit(text: liveBuffer)
                    inLiveMode = false; liveBuffer = ""; buffer = ""
                    return nil
                }
                if nsEvent.keyCode == 53 {
                    liveDelegate?.liveCommandDidCancel()
                    inLiveMode = false; liveBuffer = ""; buffer = ""
                    return nil
                }
                if nsEvent.keyCode == 51 {
                    if !liveBuffer.isEmpty { liveBuffer.removeLast() }
                    liveDelegate?.liveCommandDidUpdate(text: liveBuffer)
                    return nil
                }
                if let chars = nsEvent.characters, let scalar = chars.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) {
                    liveBuffer.append(chars)
                    liveDelegate?.liveCommandDidUpdate(text: liveBuffer)
                    return nil
                }
            }

            let trigger = currentTrigger.lowercased()
            if nsEvent.keyCode == 36 || nsEvent.keyCode == 76 {
                let lower = buffer.lowercased()
                if lower.hasPrefix(trigger) {
                    var remainder = String(buffer.dropFirst(trigger.count))
                    remainder = normalizeQuotes(remainder).trimmingCharacters(in: .whitespacesAndNewlines)
                    var extracted = ""
                    if let first = remainder.first, openingQuotes.contains(first) {
                        let closing = closingMap[first] ?? first
                        remainder.removeFirst()
                        if let endIndex = remainder.firstIndex(of: closing) { extracted = String(remainder[..<endIndex]) } else { extracted = remainder }
                    } else { extracted = remainder }
                    extracted = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !extracted.isEmpty {
                        deleteBuffer(); onTrigger(extracted); buffer = ""; delegate?.keyboardMonitorDidExitCommandMode()
                        return nil
                    }
                }
                buffer = ""; delegate?.keyboardMonitorDidExitCommandMode()
                return Unmanaged.passUnretained(event)
            }

            if nsEvent.keyCode == 51 {
                if !buffer.isEmpty { buffer.removeLast() }
                let lower = buffer.lowercased()
                if lower.hasPrefix(trigger) {
                    let preview = String(buffer.dropFirst(trigger.count))
                    delegate?.keyboardMonitor(didUpdatePreview: normalizeQuotes(preview), trigger: String(currentTrigger.dropLast()))
                } else {
                    delegate?.keyboardMonitorDidExitCommandMode()
                }
                return Unmanaged.passUnretained(event)
            }

            let normalized = normalizeQuotes(characters); buffer += normalized
            let suffixes = ["@", "@c", "@cr", "@cra", "@crai", "@craig"]
            if suffixes.contains(where: { buffer.lowercased().hasSuffix($0) }) {
                delegate?.keyboardMonitorDidEnterCommandMode(trigger: "@craig")
                delegate?.keyboardMonitor(didUpdatePreview: "Press Tab to autocomplete", trigger: "@craig")
            }
            if buffer.count > 500 { buffer = String(buffer.suffix(500)) }
            let lower = buffer.lowercased()
            if lower.hasPrefix(trigger) {
                delegate?.keyboardMonitorDidEnterCommandMode(trigger: String(currentTrigger.dropLast()))
                let preview = String(buffer.dropFirst(trigger.count))
                delegate?.keyboardMonitor(didUpdatePreview: normalizeQuotes(preview), trigger: String(currentTrigger.dropLast()))
            } else if !trigger.hasPrefix(lower) && lower.count >= trigger.count {
                delegate?.keyboardMonitorDidExitCommandMode(); buffer = ""
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func deleteBuffer() {
        let deleteCount = buffer.count
        #if DEBUG
        print("🗑️ Deleting \(deleteCount) characters")
        #endif
        DispatchQueue.main.async {
            for _ in 0..<deleteCount {
                let source = CGEventSource(stateID: .hidSystemState)
                let deleteDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
                let deleteUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
                deleteDown?.post(tap: .cghidEventTap); deleteUp?.post(tap: .cghidEventTap)
            }
        }
    }

    private func typeText(_ text: String) {
        DispatchQueue.main.async {
            let source = CGEventSource(stateID: .hidSystemState)
            for ch in text {
                let scalars = Array(String(ch).utf16)
                var uniChars = scalars.map { UniChar($0) }
                let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                uniChars.withUnsafeBufferPointer { buf in eventDown?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress) }
                let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                uniChars.withUnsafeBufferPointer { buf in eventUp?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress) }
                eventDown?.post(tap: .cghidEventTap); eventUp?.post(tap: .cghidEventTap)
            }
        }
    }

    deinit {
        if let eventTap = eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes) }
    }
}
