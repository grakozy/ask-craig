//
//  KeyboardMonitor.swift
//  Craig
//
//  Created by User on 2025-12-01.
//

import Cocoa

/// A class that monitors global key events to detect slash command triggers and notify when a valid command is entered.
final class KeyboardMonitor {
    
    /// The type of the callback called when a slash command is detected.
    typealias CommandHandler = (_ command: String, _ query: String) -> Void
    
    /// The supported trigger phrases (case-insensitive).
    private let supportedTriggers: [String]
    
    /// The currently active trigger phrase.
    private var activeTrigger: String
    
    /// The callback to invoke when a valid command is detected.
    private let onCommand: CommandHandler
    
    /// The event tap for monitoring key events.
    private var eventTap: CFMachPort?
    
    /// The run loop source for the event tap.
    private var runLoopSource: CFRunLoopSource?
    
    /// The buffer that accumulates typed characters.
    private var buffer = ""
    
    /// Initializes the keyboard monitor with supported triggers, the active trigger, and callback.
    /// - Parameters:
    ///   - supportedTriggers: The list of supported triggers.
    ///   - activeTrigger: The currently active trigger phrase.
    ///   - onCommand: The callback handler when a command is detected.
    init(supportedTriggers: [String], activeTrigger: String, onCommand: @escaping CommandHandler) {
        self.supportedTriggers = supportedTriggers.map { $0.lowercased() }
        self.activeTrigger = activeTrigger.lowercased()
        self.onCommand = onCommand
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    /// Updates the active trigger phrase.
    /// - Parameter newTrigger: The new trigger phrase.
    func updateActiveTrigger(_ newTrigger: String) {
        activeTrigger = newTrigger.lowercased()
        clearBuffer()
    }
    
    /// Starts the global key event monitoring.
    private func startMonitoring() {
        guard eventTap == nil else { return }
        
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        
        eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                     place: .headInsertEventTap,
                                     options: .defaultTap,
                                     eventsOfInterest: mask,
                                     callback: eventTapCallback,
                                     userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
        
        guard let eventTap = eventTap else {
            NSLog("Craig: Failed to create event tap")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    /// Stops the global key event monitoring.
    private func stopMonitoring() {
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }
    
    /// Clears the internal buffer.
    private func clearBuffer() {
        buffer = ""
    }
    
    /// Callback function for the CGEvent tap.
    private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handleEvent(proxy: proxy, type: type, event: event)
    }
    
    /// Handles a key down event.
    /// - Parameters:
    ///   - proxy: The event proxy.
    ///   - type: The CGEvent type.
    ///   - event: The CGEvent instance.
    /// - Returns: The possibly modified event or nil to suppress.
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        
        guard let keycode = CGKeyCode(exactly: event.getIntegerValueField(.keyboardEventKeycode)) else {
            return Unmanaged.passUnretained(event)
        }
        
        // Get the Unicode character from the key event
        guard let chars = characters(from: event), chars.count == 1 else {
            return Unmanaged.passUnretained(event)
        }
        
        let char = chars.lowercased()
        
        // Append only printable ASCII characters (space included)
        if let asciiValue = char.unicodeScalars.first?.value,
           asciiValue >= 0x20 && asciiValue <= 0x7E {
            buffer.append(char)
            
            // Limit buffer length to 500
            if buffer.count > 500 {
                buffer.removeFirst(buffer.count - 500)
            }
            
            // Determine if buffer should be reset
            if !isBufferPrefixOfAnyTrigger(buffer) {
                clearBuffer()
                return Unmanaged.passUnretained(event)
            }
            
            // If Return key pressed and buffer starts with active trigger and has a non-empty query
            if event.getIntegerValueField(.keyboardEventKeycode) == 36 { // Return keycode = 36
                if buffer.starts(with: activeTrigger),
                   buffer.count > activeTrigger.count {
                    // Extract query (after trigger)
                    let query = String(buffer.dropFirst(activeTrigger.count))
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Clear buffer before invoking callback to avoid duplicate triggers
                        clearBuffer()
                        // Call the handler on main thread
                        DispatchQueue.main.async {
                            self.onCommand(self.activeTrigger, query)
                        }
                        // Suppress the Return event to avoid inserting newline
                        return nil
                    }
                }
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
    
    /// Checks if the given buffer is a prefix of any supported triggers (case-insensitive).
    /// If the buffer length is greater than active trigger length, only compare with active trigger.
    /// - Parameter buffer: The current buffer string.
    /// - Returns: True if buffer is prefix of any trigger, otherwise false.
    private func isBufferPrefixOfAnyTrigger(_ buffer: String) -> Bool {
        let lowerBuffer = buffer.lowercased()
        
        if lowerBuffer.count > activeTrigger.count {
            // Only check against active trigger prefix when buffer is longer than active trigger
            return activeTrigger.hasPrefix(lowerBuffer) || lowerBuffer.hasPrefix(activeTrigger)
        } else {
            // Check all supported triggers for any prefix match
            return supportedTriggers.contains(where: { $0.hasPrefix(lowerBuffer) })
        }
    }
    
    /// Extracts characters from a CGEvent based on keyboard layout.
    /// - Parameter event: The CGEvent to extract characters from.
    /// - Returns: The string representation of the key pressed, or nil.
    private func characters(from event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        
        let keyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData)
        
        guard let data = layoutData else { return nil }
        let ptr = unsafeBitCast(data, to: CFData.self)
        guard let keyboardLayout = CFDataGetBytePtr(ptr) else { return nil }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = event.flags.rawValue & UInt64(NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue)
        
        let keyboardType = UInt32(LMGetKbdType())
        
        let error = UCKeyTranslate(keyboardLayout,
                                   keyCode,
                                   UInt16(kUCKeyActionDown),
                                   UInt32((modifiers >> 16) & 0xFF),
                                   keyboardType,
                                   UInt32(kUCKeyTranslateNoDeadKeysBit),
                                   &length,
                                   4,
                                   &length,
                                   &chars)
        
        if error != noErr {
            return nil
        }
        
        return String(utf16CodeUnits: chars, count: length)
    }
}
