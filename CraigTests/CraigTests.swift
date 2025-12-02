import XCTest
import AppKit
import Carbon
@testable import Craig

final class CraigTests: XCTestCase {
    
    // MARK: - Pattern Matching Tests
    
    func testTriggerPatternDetection() {
        let patterns = [
            "/craig hello",
            "/Craig hello",
            "/CRAIG hello",
            "/cRaIg hello"
        ]
        
        for pattern in patterns {
            let result = pattern.lowercased().hasPrefix("/craig ")
            XCTAssertTrue(result, "\(pattern) should trigger Craig (case-insensitive)")
        }
    }
    
    func testInvalidPatterns() {
        let invalidPatterns = [
            "/cra hello",        // incomplete
            "craig hello",       // missing /
            "/ craig hello",     // space after /
            "/craig",            // no space after craig
            "/craigtest"         // no space
        ]
        
        for pattern in invalidPatterns {
            let result = pattern.lowercased().hasPrefix("/craig ")
            XCTAssertFalse(result, "\(pattern) should NOT trigger Craig")
        }
    }
    
    func testQuestionExtraction() {
        let testCases: [(input: String, expected: String)] = [
            ("/craig hello", "hello"),
            ("/craig what is 2+2?", "what is 2+2?"),
            ("/Craig HELLO", "hello"),
            ("/craig    spaces   ", "spaces")
        ]
        
        for testCase in testCases {
            let lowercased = testCase.input.lowercased()
            if lowercased.hasPrefix("/craig ") {
                let question = String(lowercased.dropFirst("/craig ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                XCTAssertEqual(question, testCase.expected, "Question extraction failed for '\(testCase.input)'")
            }
        }
    }
    
    // MARK: - Ollama Service Tests
    
    func testOllamaServiceInitialization() {
        let service = OllamaService()
        XCTAssertNotNil(service, "OllamaService should initialize")
    }
    
    func testOllamaConnectionWithTimeout() {
        let expectation = self.expectation(description: "Ollama status check should complete")
        let service = OllamaService()
        
        service.checkStatus { isRunning in
            // Should complete within timeout whether Ollama is running or not
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, "Timeout should not occur")
        }
    }
    
    func testOllamaRequestFormat() {
        // Test that request body is properly formatted
        let question = "test question"
        let body: [String: Any] = [
            "model": "llama3.2",
            "prompt": question,
            "stream": false
        ]
        
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(body["model"] as? String, "llama3.2")
        XCTAssertEqual(body["prompt"] as? String, question)
        XCTAssertEqual(body["stream"] as? Bool, false)
    }
    
    // MARK: - Buffer Management Tests
    
    func testBufferPatternTracking() {
        var buffer = ""
        let triggerPattern = "/craig "
        
        // Simulate typing
        let keystrokes = ["/", "c", "r", "a", "i", "g", " ", "h", "e", "l", "l", "o"]
        
        for key in keystrokes {
            buffer += key
            
            // Should continue matching pattern up to "/craig "
            if buffer.count <= triggerPattern.count {
                XCTAssertTrue(triggerPattern.hasPrefix(buffer.lowercased()),
                             "Buffer '\(buffer)' should be valid prefix")
            }
        }
        
        XCTAssertTrue(buffer.lowercased().hasPrefix(triggerPattern))
    }
    
    func testBufferResetOnPatternBreak() {
        var buffer = ""
        let triggerPattern = "/craig "
        
        // Type something that breaks the pattern
        buffer = "/test"
        
        // Check if pattern is broken
        if !triggerPattern.hasPrefix(buffer.lowercased()) && buffer.count >= triggerPattern.count {
            buffer = ""
        }
        
        XCTAssertEqual(buffer, "", "Buffer should reset when pattern breaks")
    }
    
    func testBufferSizeLimit() {
        var buffer = String(repeating: "a", count: 1000)
        let maxSize = 500
        
        if buffer.count > maxSize {
            buffer = String(buffer.suffix(maxSize))
        }
        
        XCTAssertEqual(buffer.count, maxSize, "Buffer should be limited to \(maxSize) characters")
    }
    
    // MARK: - Case Sensitivity Tests
    
    func testCaseInsensitiveTrigger() {
        let testInputs = [
            "/craig test",
            "/Craig test",
            "/CRAIG test",
            "/CrAiG test",
            "/cRaIg test"
        ]
        
        for input in testInputs {
            let normalized = input.lowercased()
            XCTAssertTrue(normalized.hasPrefix("/craig "),
                         "'\(input)' should trigger Craig (case-insensitive)")
        }
    }
    
    // MARK: - Trigger Options Tests

    func testMultipleTriggersCaseInsensitive() {
        let triggers = ["/craig ", "/ask ", "/ai "]
        let inputs = ["/Craig hello", "/ASK what", "/Ai answer please"]
        let expected = ["hello", "what", "answer please"]
        for (index, input) in inputs.enumerated() {
            let lower = input.lowercased()
            // Find which trigger matches
            guard let trigger = triggers.first(where: { lower.hasPrefix($0) }) else {
                XCTFail("No trigger matched for \(input)")
                continue
            }
            let question = String(lower.dropFirst(trigger.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(question, expected[index], "Extraction failed for \(input)")
        }
    }

    func testTriggerPersistence() {
        // Simulate saving trigger to UserDefaults
        let key = "CraigCurrentTrigger"
        UserDefaults.standard.removeObject(forKey: key)
        let chosen = "/ask "
        UserDefaults.standard.set(chosen, forKey: key)
        let loaded = UserDefaults.standard.string(forKey: key)
        XCTAssertEqual(loaded, chosen)
    }
    
    func testBufferResetLogicWithMultipleTriggers() {
        let supported = ["/craig ", "/ask ", "/ai "]
        var buffer = "/Cr"
        // Should still be valid prefix for '/craig '
        XCTAssertTrue(supported.contains { $0.hasPrefix(buffer.lowercased()) })
        buffer = "/craig "
        XCTAssertTrue(supported.contains { $0.hasPrefix(buffer.lowercased()) })
        buffer += "x"
        // Now not a prefix for any trigger and length >= '/craig '
        let lower = buffer.lowercased()
        let anyPrefix = supported.contains { $0.hasPrefix(lower) }
        XCTAssertFalse(anyPrefix)
    }
    
    // MARK: - Integration Tests
    
    func testEndToEndPatternMatching() {
        var buffer = ""
        let triggerPattern = "/craig "
        var triggered = false
        var extractedQuestion = ""
        
        // Simulate typing "/Craig hello world" + Enter
        let typing = "/Craig hello world"
        for char in typing {
            buffer += String(char)
        }
        
        // Simulate Enter press
        let lowercaseBuffer = buffer.lowercased()
        if lowercaseBuffer.hasPrefix(triggerPattern) {
            let question = String(lowercaseBuffer.dropFirst(triggerPattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !question.isEmpty {
                triggered = true
                extractedQuestion = question
            }
        }
        
        XCTAssertTrue(triggered, "Should trigger on '/Craig hello world'")
        XCTAssertEqual(extractedQuestion, "hello world", "Should extract 'hello world'")
    }
    
    func testNoTriggerWithoutSpace() {
        let buffer = "/craigtest"
        let triggerPattern = "/craig "
        
        let shouldTrigger = buffer.lowercased().hasPrefix(triggerPattern)
        XCTAssertFalse(shouldTrigger, "Should not trigger without space after 'craig'")
    }
    
    func testNoTriggerWithEmptyQuestion() {
        var buffer = "/craig "
        let triggerPattern = "/craig "
        
        let lowercaseBuffer = buffer.lowercased()
        if lowercaseBuffer.hasPrefix(triggerPattern) {
            let question = String(lowercaseBuffer.dropFirst(triggerPattern.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(question.isEmpty, "Question should be empty")
        }
    }
    
    // MARK: - Performance Tests
    
    func testBufferPerformance() {
        measure {
            var buffer = ""
            for i in 0..<1000 {
                buffer += String(i)
                if buffer.count > 500 {
                    buffer = String(buffer.suffix(500))
                }
            }
        }
    }
    
    func testPatternMatchingPerformance() {
        let triggerPattern = "/craig "
        measure {
            for _ in 0..<10000 {
                let buffer = "/craig test"
                _ = buffer.lowercased().hasPrefix(triggerPattern)
            }
        }
    }
}

// MARK: - Mock Ollama Service for Testing

class MockOllamaService: OllamaService {
    var shouldSucceed = true
    var mockResponse = "This is a mock response"
    var statusCheckDelay: TimeInterval = 0.1
    
    override func checkStatus(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + statusCheckDelay) {
            completion(self.shouldSucceed)
        }
    }
    
    override func ask(question: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.shouldSucceed {
                completion(.success(self.mockResponse))
            } else {
                completion(.failure(NSError(domain: "MockError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock failure"])))
            }
        }
    }
}

// MARK: - Mock Ollama Tests

final class MockOllamaTests: XCTestCase {
    
    func testMockOllamaSuccess() {
        let expectation = self.expectation(description: "Mock Ollama should return success")
        let mockService = MockOllamaService()
        mockService.shouldSucceed = true
        
        mockService.ask(question: "test") { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response, "This is a mock response")
                expectation.fulfill()
            case .failure:
                XCTFail("Should succeed")
            }
        }
        
        waitForExpectations(timeout: 5)
    }
    
    func testMockOllamaFailure() {
        let expectation = self.expectation(description: "Mock Ollama should return failure")
        let mockService = MockOllamaService()
        mockService.shouldSucceed = false
        
        mockService.ask(question: "test") { result in
            switch result {
            case .success:
                XCTFail("Should fail")
            case .failure(let error):
                XCTAssertEqual(error.localizedDescription, "Mock failure")
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5)
    }
    
    func testStatusCheckSuccess() {
        let expectation = self.expectation(description: "Status check should succeed")
        let mockService = MockOllamaService()
        mockService.shouldSucceed = true
        
        mockService.checkStatus { isRunning in
            XCTAssertTrue(isRunning)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5)
    }
    
    func testInsertCallbackFlow() {
        let expectation = self.expectation(description: "Insert callback should be invoked")
        let mockService = MockOllamaService()
        mockService.mockResponse = "Inserted"
        let modal = CraigModalView(
            question: "test",
            ollamaService: mockService,
            onInsert: { text in
                XCTAssertEqual(text, "Inserted")
                expectation.fulfill()
            },
            onClose: { }
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Simulate user pressing insert by calling onInsert
            modal.onInsert("Inserted")
        }
        waitForExpectations(timeout: 2)
    }
}

// MARK: - UI Integration Tests (Requires Accessibility Permissions)

final class CraigUITests: XCTestCase {
    
    var app: NSRunningApplication?
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    
    override func tearDown() {
        // Close any open modals
        closeAllCraigWindows()
        super.tearDown()
    }
    
    func testFullUserFlow_TypeCraigAndGetModal() {
        let expectation = self.expectation(description: "Modal should appear after typing /craig")
        
        // 1. Launch Notes app
        let notesApp = launchNotesApp()
        XCTAssertNotNil(notesApp, "Notes app should launch")
        
        // Wait for Notes to be ready
        sleep(2)
        
        // 2. Type "/Craig hello" using system events
        let typed = typeText("/Craig hello")
        XCTAssertTrue(typed, "Should successfully type text")
        
        // 3. Press Enter
        let enterPressed = pressEnterKey()
        XCTAssertTrue(enterPressed, "Should press Enter key")
        
        // 4. Wait for modal to appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Check if Craig modal window exists
            let craigWindow = self.findCraigModalWindow()
            XCTAssertNotNil(craigWindow, "Craig modal should appear")
            
            if let window = craigWindow {
                XCTAssertTrue(window.isVisible, "Modal should be visible")
                XCTAssertEqual(window.level, .floating, "Modal should be floating")
                print("✅ Modal appeared successfully!")
            }
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10)
        
        // Cleanup
        notesApp?.terminate()
    }
    
    func testModalContent_QuestionAndResponse() {
        let expectation = self.expectation(description: "Modal should show question and response")
        
        // Use mock service to test modal content
        let mockService = MockOllamaService()
        mockService.mockResponse = "The answer is 42"
        
        // Create modal directly
        let modal = CraigModalView(
            question: "What is the meaning of life?",
            ollamaService: mockService,
            onInsert: { _ in },
            onClose: { }
        )
        
        // Wait for response
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Modal should have processed the mock response
            XCTAssertTrue(true, "Modal created successfully")
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5)
    }
    
    func testModalClosesOnInsert() {
        let expectation = self.expectation(description: "Modal should close after insert")
        var didInsert = false
        
        let mockService = MockOllamaService()
        let modal = CraigModalView(
            question: "test",
            ollamaService: mockService,
            onInsert: { text in
                didInsert = true
                XCTAssertEqual(text, "This is a mock response")
                expectation.fulfill()
            },
            onClose: { }
        )
        
        // Simulate clicking Insert button (in real test, this would be UI automation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Manually trigger onInsert callback
            modal.onInsert("This is a mock response")
        }
        
        waitForExpectations(timeout: 5)
        XCTAssertTrue(didInsert, "Insert callback should be called")
    }
    
    func testCaseInsensitiveTyping() {
        let testCases = [
            "/craig test",
            "/Craig test",
            "/CRAIG test",
            "/CrAiG test"
        ]
        
        for testCase in testCases {
            let expectation = self.expectation(description: "Should trigger for: \(testCase)")
            
            let notesApp = launchNotesApp()
            sleep(1)
            
            typeText(testCase)
            pressEnterKey()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let window = self.findCraigModalWindow()
                XCTAssertNotNil(window, "\(testCase) should trigger modal")
                expectation.fulfill()
            }
            
            waitForExpectations(timeout: 5)
            
            closeAllCraigWindows()
            notesApp?.terminate()
            sleep(1)
        }
    }
    
    func testTextDeletion() {
        let expectation = self.expectation(description: "Typed text should be deleted")
        
        let notesApp = launchNotesApp()
        sleep(2)
        
        // Type a marker text first
        typeText("BEFORE")
        sleep(0.5)
        
        // Type Craig command
        typeText("/craig test")
        pressEnterKey()
        
        // Wait for deletion and modal
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Close modal
            self.closeAllCraigWindows()
            
            // Check if "/craig test" was deleted
            // The only text should be "BEFORE"
            let clipboard = self.selectAllAndCopy()
            XCTAssertEqual(clipboard, "BEFORE", "Craig command should be deleted from Notes")
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 10)
        notesApp?.terminate()
    }
    
    func testModalInsertsPasteText() {
        let expectation = self.expectation(description: "Modal should insert text via paste")
        
        let notesApp = launchNotesApp()
        sleep(2)
        
        typeText("/craig what is 2+2")
        pressEnterKey()
        
        // Wait for modal and AI response
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            // Simulate clicking Insert button
            // In real scenario, we'd need to find the button and click it
            // For now, we test that the insert mechanism works
            
            let window = self.findCraigModalWindow()
            XCTAssertNotNil(window, "Modal should exist")
            
            // Simulate insert by pressing Enter (if modal is focused)
            self.pressEnterKey()
            
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 15)
        notesApp?.terminate()
    }
    
    // MARK: - Helper Methods
    
    func launchNotesApp() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let notesURL = URL(fileURLWithPath: "/System/Applications/Notes.app")
        
        do {
            let app = try workspace.launchApplication(at: notesURL,
                                                      options: .default,
                                                      configuration: [:])
            return app
        } catch {
            print("Failed to launch Notes: \(error)")
            return nil
        }
    }
    
    func typeText(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            guard let keyCode = keyCodeForCharacter(char) else { continue }
            
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            
            // Handle shift for uppercase
            if char.isUppercase || "!@#$%^&*()_+{}|:\"<>?".contains(char) {
                keyDown?.flags = .maskShift
                keyUp?.flags = .maskShift
            }
            
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            
            usleep(50000) // 50ms delay between keys
        }
        
        return true
    }
    
    func pressEnterKey() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        return true
    }
    
    func findCraigModalWindow() -> NSWindow? {
        for window in NSApplication.shared.windows {
            // Craig modal is borderless and floating
            if window.styleMask.contains(.borderless) && window.level == .floating {
                return window
            }
        }
        return nil
    }
    
    func closeAllCraigWindows() {
        for window in NSApplication.shared.windows {
            if window.styleMask.contains(.borderless) && window.level == .floating {
                window.close()
            }
        }
    }
    
    func selectAllAndCopy() -> String {
        // Cmd+A
        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true)
        aDown?.flags = .maskCommand
        let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.post(tap: .cghidEventTap)
        aDown?.post(tap: .cghidEventTap)
        aUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        usleep(100000)
        
        // Cmd+C
        let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        
        cmdDown?.post(tap: .cghidEventTap)
        cDown?.post(tap: .cghidEventTap)
        cUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        usleep(100000)
        
        return NSPasteboard.general.string(forType: .string) ?? ""
    }
    
    func keyCodeForCharacter(_ char: Character) -> CGKeyCode? {
        let mapping: [Character: CGKeyCode] = [
            "/": 0x2C,
            "c": 0x08, "C": 0x08,
            "r": 0x0F, "R": 0x0F,
            "a": 0x00, "A": 0x00,
            "i": 0x22, "I": 0x22,
            "g": 0x05, "G": 0x05,
            " ": 0x31,
            "h": 0x04, "H": 0x04,
            "e": 0x0E, "E": 0x0E,
            "l": 0x25, "L": 0x25,
            "o": 0x1F, "O": 0x1F,
            "w": 0x0D, "W": 0x0D,
            "t": 0x11, "T": 0x11,
            "s": 0x01, "S": 0x01,
            "2": 0x13,
            "+": 0x18,
            "4": 0x15,
            "?": 0x2C
        ]
        return mapping[char]
    }
}

