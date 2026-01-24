import Foundation
import Combine
import ApplicationServices
import AppKit

/// Arrow key directions for navigation
enum ArrowDirection {
    case left
    case right
    case up
    case down
}

/// Keyboard modifiers for special key combinations
enum KeyModifier {
    case option
    case command
    case shift
}

/// Typing states for TypingManager (defined outside class for Swift 6 Sendable conformance)
enum TypingState: Sendable, Equatable {
    case idle
    case countingDown
    case typing
    case editing
    case paused
}

/// Errors that can occur during the editing phase
enum EditingError: Error, LocalizedError, Sendable, Equatable {
    case focusLostDuringEdit
    case keyboardEventFailed
    case unexpectedState(String)

    var errorDescription: String? {
        switch self {
        case .focusLostDuringEdit:
            return "Focus was lost during editing. The document may be partially edited."
        case .keyboardEventFailed:
            return "Failed to send keyboard events to the target application."
        case .unexpectedState(let details):
            return "An unexpected error occurred: \(details)"
        }
    }

    var recoverySuggestion: String? {
        return "You can use Cmd+Z to undo any changes made before the error occurred."
    }
}

final class TypingManager: NSObject, ObservableObject {

    // Backwards editing state removed - now using EditWithPosition from EditOperationConverter

    @Published var state: TypingState = .idle
    @Published var countdownRemaining: Int = 0
    @Published var progressText: String = ""
    @Published var isThinking: Bool = false
    @Published var lastCompletionDate: Date?
    @Published var lastRunDuration: TimeInterval?
    @Published var lastTypingPhaseDuration: TimeInterval?
    @Published var lastEditingPhaseDuration: TimeInterval?
    @Published var progressFraction: Double = 0.0  // 0.0 = not started, 1.0 = complete
    @Published var lastEditingError: EditingError?  // Set when editing fails, cleared after handling

    private var countdownTimer: Timer?
    private var typingStartDate: Date?
    private var editingStartDate: Date?
    
    // Typing state
    private var textToType: [Character] = []
    private var currentIndex: Int = 0
    private var interCharacterDelay: TimeInterval = 0.05
    
    // Jitter / thinking state
    private var previousCharacter: Character?
    private var wordsSinceLastThinkingPause: Int = 0
    private var wordsUntilNextThinkingPause: Int = Int.random(in: 3...5)
    
    // Mistake simulation
    private var shouldSimulateMistakes: Bool = false
    private var charactersTypedSinceLastMistake: Int = 0
    private var nextMistakeInCharacters: Int = Int.random(in: 50...75)
    
    
    private let transitionWords: Set<String> = [
        "however",
        "nevertheless",
        "because",
        "but",
        "therefore"
    ]
    
    private var typingWorkItem: DispatchWorkItem?
    
    // Total-time related
    private var extraDelayPerSentenceEnd: TimeInterval = 0
    private var extraDelayPerParagraphBreak: TimeInterval = 0
    
    // Focus tracking - track specific window, not just app
    private var targetWindowTitle: String?
    private var targetAppPID: pid_t?  // Keep as backup for window title comparison

    // Global Esc key handling
    private var escEventTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?

    // Backwards editing state
    private var draft1Text: String?                      // Original text (Draft 1)
    private var draft2Text: String?                      // Target text (Draft 2)
    private var positionedEdits: [EditWithPosition] = [] // Edit operations with positions (sorted right-to-left)
    private var currentEditIndex: Int = 0                // Current edit being executed
    private var actualCursorPosition: Int = 0            // Actual cursor position in the modified text
    private var customEditingDuration: TimeInterval?
    private var extraDelayPerEdit: TimeInterval = 0      // Extra delay between edits for custom duration

    // Edit-phase character typing state (mirrors typing phase for reliability)
    private var editCharsToType: [Character] = []        // Characters being inserted during an edit
    private var editCharIndex: Int = 0                   // Current index in editCharsToType
    private var editCharCompletion: (() -> Void)?        // Completion handler when done typing
    private var editCharWorkItem: DispatchWorkItem?      // Cancellable work item for edit typing
    private var editCharPreviousChar: Character?         // Previous character for extra delay calculation

    // Editing delay configuration - multiplier for editing phase delays
    private var editingDelayMultiplier: Double = 1.0

    // Periodic focus checker (safety net for missed window switches)
    private var focusCheckTimer: Timer?

    // Tracks which state we were in before pausing (to resume correctly)
    private var stateBeforePause: TypingState?

    // Sleep prevention - prevents system idle sleep during active typing/editing
    private var sleepPreventionActivity: NSObjectProtocol?

    override init() {
        super.init()
        
        // Listen for app activation changes globally
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveAppChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        setupEscEventTap()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        if let source = escRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        // Clean up sleep prevention if still active
        if let activity = sleepPreventionActivity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }
    
    func startTyping(
        text: String,
        wpm: Int,
        countdown: Int = 10,
        totalDurationSeconds: TimeInterval? = nil,
        simulateMistakes: Bool = false
    ) {
        // Reset any existing timers/state
        countdownTimer?.invalidate()
        typingWorkItem?.cancel()

        textToType = Array(text)
        currentIndex = 0
        previousCharacter = nil
        wordsSinceLastThinkingPause = 0
        wordsUntilNextThinkingPause = Int.random(in: 3...5)
        shouldSimulateMistakes = simulateMistakes
        charactersTypedSinceLastMistake = 0
        nextMistakeInCharacters = Int.random(in: 50...75)
        extraDelayPerSentenceEnd = 0
        extraDelayPerParagraphBreak = 0
        isThinking = false
        targetAppPID = nil
        stateBeforePause = nil
        typingStartDate = nil
        lastRunDuration = nil
        progressFraction = 0.0

        guard !textToType.isEmpty else {
            state = .idle
            progressText = "Nothing to type."
            return
        }

        // Base typing speed ALWAYS comes from WPM.
        let charsPerMinute = max(5.0, Double(wpm) * 5.0)
        interCharacterDelay = 60.0 / charsPerMinute

        if let totalDurationSeconds {
            // Base typing time from pure WPM.
            let baseTypingTime = Double(textToType.count) * interCharacterDelay

            // Rough estimate of extra time introduced by human-like jitter
            // (thinking pauses, commas, mistakes, etc.). This helps keep
            // the requested duration closer to reality.
            let jitterMultiplier = 1.0
            let estimatedJitter = baseTypingTime * jitterMultiplier
            let baseWithJitter = baseTypingTime + estimatedJitter

            let extraBudget = max(0, totalDurationSeconds - baseWithJitter)

            if extraBudget > 0 {
                let counts = countSentencesAndParagraphs(in: textToType)
                let sentenceCount = counts.sentences
                let paragraphCount = counts.paragraphs

                let weightedSlots = Double(sentenceCount) + Double(paragraphCount) * 2.0
                if weightedSlots > 0 {
                    let unit = extraBudget / weightedSlots
                    extraDelayPerSentenceEnd = unit
                    extraDelayPerParagraphBreak = unit * 2.0
                }
            }

            let minutes = Int(totalDurationSeconds / 60)
            progressText = "Ready to type \(text.count) characters at \(wpm) WPM over at least \(minutes) minute(s), with longer pauses between sentences and paragraphs."
        } else {
            progressText = "Ready to type \(text.count) characters at \(wpm) WPM."
        }

        countdownRemaining = countdown
        state = .countingDown

        // Start countdown
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            DispatchQueue.main.async {
                if self.countdownRemaining > 0 {
                    self.countdownRemaining -= 1
                } else {
                    timer.invalidate()
                    self.beginTypingLoop()
                }
            }
        }
    }
    
    func stopTyping() {
        countdownTimer?.invalidate()
        countdownTimer = nil

        typingWorkItem?.cancel()
        typingWorkItem = nil

        // Cancel edit character typing work item
        editCharWorkItem?.cancel()
        editCharWorkItem = nil
        editCharCompletion = nil
        editCharsToType = []

        stopPeriodicFocusCheck()
        endSleepPrevention()

        state = .idle
        countdownRemaining = 0
        progressText = ""
        isThinking = false
        targetAppPID = nil
        targetWindowTitle = nil
        stateBeforePause = nil
        lastCompletionDate = nil
        lastTypingPhaseDuration = nil
        lastEditingPhaseDuration = nil
        editingStartDate = nil
        extraDelayPerEdit = 0
        progressFraction = 0.0
        lastEditingError = nil
    }
    
    // MARK: - Private typing logic
    
    private func beginTypingLoop() {
        guard !textToType.isEmpty else {
            state = .idle
            progressText = "Nothing to type."
            return
        }

        typingStartDate = Date()
        progressFraction = 0.0

        // At the moment typing begins, record the current frontmost app and window
        // as the intended typing target.
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        targetAppPID = frontmostApp?.processIdentifier
        targetWindowTitle = getFocusedWindowTitle()

        appLog("Target app recorded - PID: \(targetAppPID ?? 0), name: '\(frontmostApp?.localizedName ?? "unknown")', window: '\(targetWindowTitle ?? "unknown")'", level: .debug)

        state = .typing
        progressText = "Typing in progress…"
        isThinking = false

        // Prevent system idle sleep during active typing
        beginSleepPrevention()

        // Start periodic focus check (every 0.5 seconds) as safety net
        startPeriodicFocusCheck()

        scheduleNextCharacter(after: interCharacterDelay)
    }
    
    private func scheduleNextCharacter(after delay: TimeInterval) {
        guard currentIndex < textToType.count else {
            finishTyping()
            return
        }
        
        typingWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.typeNextCharacter()
        }
        
        typingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func typeNextCharacter() {
        guard state == .typing else { return }

        guard currentIndex < textToType.count else {
            finishTyping()
            return
        }

        // CRITICAL: Check focus BEFORE typing each character
        // This ensures we NEVER type even a single character in the wrong window
        if !isTargetWindowFocused() {
            let currentWindow = getFocusedWindowTitle()
            appLog("Focus check before character - Target: '\(targetWindowTitle ?? "none")' Current: '\(currentWindow ?? "none")'", level: .debug)
            appLog("Not in target window, pausing typing", level: .debug)
            pauseTyping()
            return
        }
        
        DispatchQueue.main.async {
            self.isThinking = false
        }
        
        let character = textToType[currentIndex]
        currentIndex += 1

        let totalCount = textToType.count
        if totalCount > 0 {
            let fraction = Double(currentIndex) / Double(totalCount)
            DispatchQueue.main.async {
                self.progressFraction = min(max(fraction, 0.0), 1.0)
            }
        }
        
        if shouldSimulateMistakes,
           shouldMakeMistakeNow(for: character) {
            performMistakeCycle(correctCharacter: character)
            return
        }
        
        sendCharacter(character)
        
        let extra = extraDelay(afterTyping: character)
        let nextDelay = interCharacterDelay + extra
        
        previousCharacter = character
        
        if currentIndex < textToType.count {
            scheduleNextCharacter(after: nextDelay)
        } else {
            finishTyping()
        }
    }
    
    private func finishTyping() {
        typingWorkItem?.cancel()
        typingWorkItem = nil

        stopPeriodicFocusCheck()

        // Record typing phase duration
        var typingDuration: TimeInterval?
        if let start = typingStartDate {
            typingDuration = Date().timeIntervalSince(start)
        }

        // Check if we need to transition to editing phase
        if let draft2 = draft2Text, !draft2.isEmpty {
            // Store typing phase duration for later reporting
            self.lastTypingPhaseDuration = typingDuration

            // Convert textToType back to string for draft1
            let draft1 = String(textToType)

            // Pause for 2 seconds before editing (simulates "reviewing Draft 1")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                self.startEditing(
                    draft1: draft1,
                    draft2: draft2,
                    customDuration: self.customEditingDuration
                )
            }
        } else {
            // Normal single-draft completion
            endSleepPrevention()
            DispatchQueue.main.async {
                if let start = self.typingStartDate {
                    self.lastRunDuration = Date().timeIntervalSince(start)
                    self.typingStartDate = nil
                }
                self.progressFraction = 1.0
                self.state = .idle
                self.lastCompletionDate = Date()
                self.progressText = "Typing complete."
                self.isThinking = false
                self.targetAppPID = nil
                self.targetWindowTitle = nil
            }
        }
    }
    
    // MARK: - Pause / resume on app focus changes
    
    @objc private func handleActiveAppChange(_ notification: Notification) {
        guard notification.userInfo?[NSWorkspace.applicationUserInfoKey] is NSRunningApplication else {
            return
        }

        guard targetAppPID != nil else {
            return
        }

        // Small delay to let window focus settle before checking window title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            let isTargetFocused = self.isTargetWindowFocused()
            let currentWindowTitle = self.getFocusedWindowTitle()

            appLog("App change - Target: '\(self.targetWindowTitle ?? "none")' Current: '\(currentWindowTitle ?? "none")' Focused: \(isTargetFocused)", level: .debug)

            switch self.state {
            case .typing:
                // If we leave the target window, pause
                if !isTargetFocused {
                    appLog("Leaving target window, pausing typing", level: .debug)
                    self.pauseTyping()
                }
            case .editing:
                // If we leave the target window during editing, abort with error
                if !isTargetFocused {
                    appLog("Leaving target window, aborting editing", level: .debug)
                    self.abortEditingWithError(.focusLostDuringEdit)
                }
            case .paused:
                // If we come back to the target window, resume
                if isTargetFocused {
                    appLog("Returned to target window, resuming", level: .debug)
                    // Use tracked state to determine whether to resume typing or editing
                    if self.stateBeforePause == .editing {
                        self.resumeEditing()
                    } else {
                        self.resumeTyping()
                    }
                    self.stateBeforePause = nil
                }
            default:
                break
            }
        }
    }
    
    private func pauseTyping() {
        guard state == .typing else { return }

        // Record what state we're pausing from (for correct resume)
        stateBeforePause = .typing

        typingWorkItem?.cancel()
        typingWorkItem = nil

        stopPeriodicFocusCheck()

        DispatchQueue.main.async {
            self.state = .paused
            self.isThinking = false
            self.progressText = "Paused. Switch back to your document to resume."
        }
    }

    // Immediate resume, for internal use when regaining app focus.
    private func resumeTyping() {
        guard state == .paused else { return }

        DispatchQueue.main.async {
            self.state = .typing
            self.progressText = "Resumed typing…"
            self.isThinking = false
        }

        // Restart periodic focus check
        startPeriodicFocusCheck()

        scheduleNextCharacter(after: interCharacterDelay)
    }

    // MARK: - Periodic Focus Checking

    /// Starts a timer to periodically check if we're still in the target window
    /// This is a safety net in case NSWorkspace notifications are missed
    private func startPeriodicFocusCheck() {
        // Stop any existing timer
        stopPeriodicFocusCheck()

        // Check every 0.5 seconds
        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // Dispatch to main actor to safely access @MainActor-isolated state
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Only check during active typing/editing states
                guard self.state == .typing || self.state == .editing else {
                    return
                }

                // Check if we're still in the target window
                if !self.isTargetWindowFocused() {
                    let currentWindow = self.getFocusedWindowTitle()
                    appLog("Periodic check detected window switch - Target: '\(self.targetWindowTitle ?? "none")' Current: '\(currentWindow ?? "none")'", level: .debug)

                    // Pause typing, abort editing with error
                    if self.state == .typing {
                        appLog("Auto-pausing typing", level: .debug)
                        self.pauseTyping()
                    } else if self.state == .editing {
                        appLog("Auto-aborting editing (window switch)", level: .debug)
                        self.abortEditingWithError(.focusLostDuringEdit)
                    }
                }
            }
        }
    }

    /// Stops the periodic focus check timer
    private func stopPeriodicFocusCheck() {
        focusCheckTimer?.invalidate()
        focusCheckTimer = nil
    }

    // MARK: - Sleep Prevention

    /// Begins preventing system and display idle sleep during active typing/editing
    private func beginSleepPrevention() {
        guard sleepPreventionActivity == nil else { return }
        sleepPreventionActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled],
            reason: "Actively typing or editing text"
        )
        appLog("Sleep prevention started", level: .debug)
    }

    /// Ends sleep prevention, allowing the system to sleep normally
    private func endSleepPrevention() {
        guard let activity = sleepPreventionActivity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        sleepPreventionActivity = nil
        appLog("Sleep prevention ended", level: .debug)
    }

    /// Gets the title of the currently focused window using Accessibility API
    private func getFocusedWindowTitle() -> String? {
        // Get the frontmost application
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused window
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)

        guard result == .success, let window = focusedWindow else {
            return nil
        }

        // Get the window's title
        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)

        guard titleResult == .success, let windowTitle = title as? String else {
            return nil
        }

        return windowTitle
    }

    private func isTargetWindowFocused() -> Bool {
        // Must have at least the target app PID to do any checking
        guard let targetPID = targetAppPID else {
            // If we don't have a recorded target app, allow typing
            appLog("No target app recorded, allowing typing", level: .debug)
            return true
        }

        // Check if the frontmost app matches
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            appLog("Can't get frontmost app PID - pausing", level: .debug)
            return false
        }

        // If app doesn't match, definitely not the right window
        if frontmostPID != targetPID {
            appLog("App PID mismatch - target: \(targetPID), current: \(frontmostPID)", level: .debug)
            return false
        }

        // App matches - if we also have a target window title, verify it too
        if let targetTitle = targetWindowTitle {
            guard let currentWindowTitle = getFocusedWindowTitle() else {
                // Can't determine current window title but app matches
                // Be conservative and assume wrong window
                appLog("Can't get current window title, being conservative", level: .debug)
                return false
            }

            // Compare window titles
            if currentWindowTitle != targetTitle {
                appLog("Window title mismatch - target: '\(targetTitle)', current: '\(currentWindowTitle)'", level: .debug)
                return false
            }
        }

        // App matches (and window title matches if we had one)
        return true
    }
    
    
    // MARK: - Jitter / thinking behaviour
    
    private func extraDelay(afterTyping character: Character) -> TimeInterval {
        var extra: TimeInterval = 0
        
        if character.isWhitespace {
            if let prev = previousCharacter, !prev.isWhitespace {
                wordsSinceLastThinkingPause += 1
                
                if wordsSinceLastThinkingPause >= wordsUntilNextThinkingPause {
                    extra += Double.random(in: 1.0...2.0)
                    wordsSinceLastThinkingPause = 0
                    wordsUntilNextThinkingPause = Int.random(in: 3...5)
                }
            }
        }
        
        if character == "," {
            extra += Double.random(in: 1.0...2.0)
        }
        
        if ".?!;:".contains(character) {
            extra += Double.random(in: 5.0...10.0)
            extra += extraDelayPerSentenceEnd
        }
        
        if character == "\n", let prev = previousCharacter, prev == "\n" {
            extra += Double.random(in: 6.0...12.0)
            extra += extraDelayPerParagraphBreak
        }
        
        if let nextWord = peekNextWord(),
           transitionWords.contains(nextWord.lowercased()) {
            extra += Double.random(in: 1.0...2.0)
        }
        
        DispatchQueue.main.async {
            self.isThinking = (extra >= 0.8)
        }
        
        return extra
    }
    
    private func peekNextWord() -> String? {
        var index = currentIndex
        let count = textToType.count
        
        while index < count, textToType[index].isWhitespace {
            index += 1
        }
        
        guard index < count else { return nil }
        
        var wordChars: [Character] = []
        
        while index < count {
            let c = textToType[index]
            if c.isLetter || c == "'" || c == "-" {
                wordChars.append(c)
                index += 1
            } else {
                break
            }
        }
        
        guard !wordChars.isEmpty else { return nil }
        return String(wordChars)
    }
    
    private func countSentencesAndParagraphs(in characters: [Character]) -> (sentences: Int, paragraphs: Int) {
        var punctuationSentences = 0
        var paragraphs = 0
        var newlineSentenceCandidates = 0

        for i in 0..<characters.count {
            let c = characters[i]

            if ".?!;:".contains(c) {
                punctuationSentences += 1
            }

            if c == "\n" {
                if i > 0, characters[i - 1] == "\n" {
                    // Double newline -> paragraph break.
                    paragraphs += 1
                } else {
                    // Single newline -> potential sentence-like boundary for fragments / bullet lists.
                    newlineSentenceCandidates += 1
                }
            }
        }

        let sentences: Int
        if punctuationSentences > 0 {
            sentences = punctuationSentences
        } else {
            // If there are no sentence-ending punctuation marks at all,
            // treat each single newline as a "sentence-like" boundary so that
            // bullet lists and short fragments can still receive extra pause time.
            sentences = newlineSentenceCandidates
        }

        return (sentences, paragraphs)
    }
    
    // MARK: - Event sending
    
    private func sendCharacter(_ character: Character) {
        let source = CGEventSource(stateID: .hidSystemState)

        // Log character sending at verbose level (very frequent)
        let unicodeVal = character.unicodeScalars.first?.value ?? 0
        appLog("sendCharacter: '\(character)' (U+\(String(format: "%04X", unicodeVal)))", level: .verbose)

        // Special-case newlines: send a real Return key event so apps treat it
        // exactly like pressing the Enter/Return key, instead of a raw "\n".
        if character == "\n" || character == "\r" {
            let returnKeyCode: CGKeyCode = 0x24 // kVK_Return

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
                return
            }

            // Explicitly clear modifier flags
            keyDown.flags = []
            keyUp.flags = []

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            return
        }
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }

        // Explicitly clear all modifier flags to prevent any flag pollution
        // from prior key events (arrow keys, forward delete, etc.)
        keyDown.flags = []
        keyUp.flags = []

        let string = String(character)
        let utf16 = Array(string.utf16)

        utf16.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }

            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)

            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Mistake simulation
    
    private func shouldMakeMistakeNow(for character: Character) -> Bool {
        // Only consider visible letters for mistakes.
        guard character.isLetter else {
            return false
        }
        
        charactersTypedSinceLastMistake += 1
        
        if charactersTypedSinceLastMistake >= nextMistakeInCharacters {
            charactersTypedSinceLastMistake = 0
            nextMistakeInCharacters = Int.random(in: 50...75)
            return true
        }
        
        return false
    }
    
    private func performMistakeCycle(correctCharacter: Character) {
        guard let wrong = randomMistypedCharacter(for: correctCharacter) else {
            // Fallback: just type the correct character normally.
            sendCharacter(correctCharacter)
            
            let extra = extraDelay(afterTyping: correctCharacter)
            let nextDelay = interCharacterDelay + extra
            previousCharacter = correctCharacter
            
            if currentIndex < textToType.count {
                scheduleNextCharacter(after: nextDelay)
            } else {
                finishTyping()
            }
            return
        }
        
        // Type the wrong character first.
        sendCharacter(wrong)
        
        // Show thinking during the delay before correction.
        DispatchQueue.main.async {
            self.isThinking = true
        }
        
        typingWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // If the user has switched apps, pause instead of correcting in the wrong place.
            if !self.isTargetWindowFocused() {
                self.pauseTyping()
                return
            }
            
            // Backspace the wrong character and type the correct one.
            self.sendBackspace()
            self.sendCharacter(correctCharacter)
            
            let extra = self.extraDelay(afterTyping: correctCharacter)
            let nextDelay = self.interCharacterDelay + extra
            self.previousCharacter = correctCharacter
            
            if self.currentIndex < self.textToType.count {
                self.scheduleNextCharacter(after: nextDelay)
            } else {
                self.finishTyping()
            }
        }
        
        typingWorkItem = workItem
        // Wait 3 seconds before correcting, to mimic a human noticing and fixing the typo.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }
    
    private func randomMistypedCharacter(for character: Character) -> Character? {
        let isUpper = character.isUppercase
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let lower = Character(character.lowercased())
        guard let index = letters.firstIndex(of: lower) else {
            return nil
        }
        
        let offsets = [-2, -1, 1, 2].shuffled()
        for offset in offsets {
            let newIndex = index + offset
            if newIndex >= 0 && newIndex < letters.count {
                let newChar = letters[newIndex]
                return isUpper ? Character(String(newChar).uppercased()) : newChar
            }
        }
        return nil
    }
    
    private func sendBackspace() {
        let source = CGEventSource(stateID: .hidSystemState)
        let backspaceKeyCode: CGKeyCode = 0x33 // Delete key (backward delete)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: false) else {
            return
        }

        // Explicitly clear modifier flags
        keyDown.flags = []
        keyUp.flags = []

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendForwardDelete() {
        let source = CGEventSource(stateID: .hidSystemState)
        let forwardDeleteKeyCode: CGKeyCode = 0x75 // Forward Delete key (fn+delete)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: forwardDeleteKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: forwardDeleteKeyCode, keyDown: false) else {
            return
        }

        // Explicitly clear modifier flags
        keyDown.flags = []
        keyUp.flags = []

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendReturnKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let returnKeyCode: CGKeyCode = 0x24  // Return key

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
            return
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendEscapeKey() {
        let source = CGEventSource(stateID: .hidSystemState)
        let escapeKeyCode: CGKeyCode = 0x35  // Escape key

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: escapeKeyCode, keyDown: false) else {
            return
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendArrowKey(_ direction: ArrowDirection, withModifier modifier: KeyModifier? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)

        let keyCode: CGKeyCode = switch direction {
            case .left: 0x7B    // kVK_LeftArrow
            case .right: 0x7C   // kVK_RightArrow
            case .up: 0x7E      // kVK_UpArrow
            case .down: 0x7D    // kVK_DownArrow
        }

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        // Explicitly set flags - either the modifier or empty
        if let modifier = modifier {
            let flags: CGEventFlags = switch modifier {
                case .option: .maskAlternate
                case .command: .maskCommand
                case .shift: .maskShift
            }
            keyDown.flags = flags
            keyUp.flags = [] // Release modifier on key up
        } else {
            // No modifier - explicitly clear all flags
            keyDown.flags = []
            keyUp.flags = []
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Editing Time Estimation

    /// Estimates the editing time for transforming draft1 into draft2 at the given WPM
    /// This can be called before starting to provide a preview estimate
    func estimateEditingTime(draft1: String, draft2: String, wpm: Int) -> TimeInterval {
        // If drafts are identical, no editing needed
        if draft1 == draft2 {
            return 0
        }

        // Compute the edit operations
        let edits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)

        if edits.isEmpty {
            return 0
        }

        // Calculate delays based on WPM (same logic as in startTyping)
        let charsPerMinute = max(5.0, Double(wpm) * 5.0)
        let baseInterCharDelay = 60.0 / charsPerMinute
        let delayMultiplier = editingDelayMultiplier

        let navigationDelay = 0.08 * delayMultiplier
        let postNavigationDelay = 0.3 * delayMultiplier
        let deleteDelay = 0.1 * delayMultiplier
        let postDeleteDelay = 0.3 * delayMultiplier
        let postInsertDelay = 0.3 * delayMultiplier
        let baseCharDelay = max(0.05, baseInterCharDelay) * delayMultiplier

        var totalTime: TimeInterval = 0
        var simulatedCursorPos = draft1.count // Start at end of draft1

        for edit in edits {
            // Navigation time
            let moveDistance = simulatedCursorPos - edit.position
            if moveDistance > 0 {
                totalTime += Double(moveDistance) * navigationDelay
                totalTime += postNavigationDelay
            }

            // Operation time
            switch edit.operation {
            case .delete(let count):
                totalTime += Double(count) * deleteDelay
                totalTime += postDeleteDelay
                simulatedCursorPos = edit.position

            case .insert(let text):
                // Base typing time
                let charCount = text.count
                totalTime += Double(charCount) * baseCharDelay
                // Add estimated jitter based on actual text content
                totalTime += estimateTextJitter(text) * delayMultiplier
                totalTime += postInsertDelay
                simulatedCursorPos = edit.position + text.count

            case .replace(let oldCount, let newText):
                totalTime += Double(oldCount) * deleteDelay
                totalTime += postDeleteDelay
                // Base typing time
                let charCount = newText.count
                totalTime += Double(charCount) * baseCharDelay
                // Add estimated jitter based on actual text content
                totalTime += estimateTextJitter(newText) * delayMultiplier
                totalTime += postInsertDelay
                simulatedCursorPos = edit.position + newText.count

            default:
                break
            }
        }

        // Add initial pause before editing starts (simulates "reviewing Draft 1")
        totalTime += 1.0

        return totalTime
    }

    // MARK: - Two-Phase Editing Mode

    func startTwoPhaseTyping(
        draft1: String,
        draft2: String,
        wpm: Int,
        countdown: Int = 10,
        typingDuration: TimeInterval? = nil,
        editingDuration: TimeInterval? = nil,
        simulateMistakes: Bool = false
    ) {
        // Store draft2 and editing duration for later use
        self.draft2Text = draft2
        self.customEditingDuration = editingDuration

        // Start with normal typing of draft1
        startTyping(
            text: draft1,
            wpm: wpm,
            countdown: countdown,
            totalDurationSeconds: typingDuration,
            simulateMistakes: simulateMistakes
        )
    }

    // MARK: - Backwards Editing

    private func startEditing(draft1: String, draft2: String, customDuration: TimeInterval?) {
        // Check if drafts are identical - skip editing if so
        if draft1 == draft2 {
            finishEditing()
            return
        }

        draft2Text = draft2
        editingStartDate = Date()

        appLog("Starting backwards editing - Draft 1: \(draft1.count) chars, Draft 2: \(draft2.count) chars", level: .info)

        // Step 1: Compute positioned edits (sorted right-to-left)
        positionedEdits = convertDraftsToPositionedEdits(draft1: draft1, draft2: draft2)
        appLog("Generated \(positionedEdits.count) positioned edits", level: .debug)

        // Step 2: Initialize editing state
        state = .editing
        progressText = "Editing Draft 1 into Draft 2…"
        progressFraction = 0.5
        isThinking = false
        currentEditIndex = 0
        actualCursorPosition = draft1.count // Cursor starts at end of draft1
        extraDelayPerEdit = 0

        // Step 3: Calculate extra delay per edit if custom duration is specified
        if let targetDuration = customDuration, targetDuration > 0, !positionedEdits.isEmpty {
            let naturalEditingTime = estimateNaturalEditingTime()
            let extraBudget = max(0, targetDuration - naturalEditingTime)

            if extraBudget > 0 {
                // Distribute extra time across all edit operations
                extraDelayPerEdit = extraBudget / Double(positionedEdits.count)
                appLog("Custom editing duration: \(targetDuration)s, natural estimate: \(naturalEditingTime)s, extra delay per edit: \(extraDelayPerEdit)s", level: .debug)
            }
        }

        // Start periodic focus check for editing phase
        startPeriodicFocusCheck()

        // Pause briefly before starting edits (simulates reviewing Draft 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.executeNextEditBackwards()
        }
    }

    /// Estimates the jitter time for typing a given text string
    /// This mirrors the extraDelay(afterTyping:) logic to provide accurate estimates
    private func estimateTextJitter(_ text: String) -> TimeInterval {
        guard !text.isEmpty else { return 0 }

        var totalJitter: TimeInterval = 0
        let chars = Array(text)
        var wordCount = 0
        var wordsUntilPause = 4 // Average of 3-5

        for i in 0..<chars.count {
            let char = chars[i]
            let prevChar: Character? = i > 0 ? chars[i - 1] : nil

            // Word boundary pauses (every 3-5 words, average 1.5s)
            if char.isWhitespace {
                if let prev = prevChar, !prev.isWhitespace {
                    wordCount += 1
                    if wordCount >= wordsUntilPause {
                        totalJitter += 1.5 // Average of 1.0-2.0
                        wordCount = 0
                        wordsUntilPause = 4 // Reset to average
                    }
                }
            }

            // Comma pause (average 1.5s)
            if char == "," {
                totalJitter += 1.5
            }

            // Sentence-ending punctuation (average 7.5s)
            if ".?!;:".contains(char) {
                totalJitter += 7.5
            }

            // Paragraph break - double newline (average 9s)
            if char == "\n", let prev = prevChar, prev == "\n" {
                totalJitter += 9.0
            }
        }

        return totalJitter
    }

    /// Estimates the natural editing time based on operations count and complexity
    private func estimateNaturalEditingTime() -> TimeInterval {
        var totalTime: TimeInterval = 0
        let navigationDelay = 0.08 * editingDelayMultiplier
        let postNavigationDelay = 0.3 * editingDelayMultiplier
        let deleteDelay = 0.1 * editingDelayMultiplier
        let postDeleteDelay = 0.3 * editingDelayMultiplier
        let postInsertDelay = 0.3 * editingDelayMultiplier
        let baseCharDelay = max(0.05, interCharacterDelay) * editingDelayMultiplier

        var simulatedCursorPos = textToType.count // Start cursor at end of typed text (draft1)

        for edit in positionedEdits {
            // Navigation time
            let moveDistance = simulatedCursorPos - edit.position
            if moveDistance > 0 {
                totalTime += Double(moveDistance) * navigationDelay
                totalTime += postNavigationDelay
            }

            // Operation time
            switch edit.operation {
            case .delete(let count):
                totalTime += Double(count) * deleteDelay
                totalTime += postDeleteDelay
                simulatedCursorPos = edit.position

            case .insert(let text):
                // Base typing time
                let charCount = text.count
                totalTime += Double(charCount) * baseCharDelay
                // Add estimated jitter based on actual text content
                totalTime += estimateTextJitter(text) * editingDelayMultiplier
                totalTime += postInsertDelay
                simulatedCursorPos = edit.position + text.count

            case .replace(let oldCount, let newText):
                totalTime += Double(oldCount) * deleteDelay
                totalTime += postDeleteDelay
                // Base typing time
                let charCount = newText.count
                totalTime += Double(charCount) * baseCharDelay
                // Add estimated jitter based on actual text content
                totalTime += estimateTextJitter(newText) * editingDelayMultiplier
                totalTime += postInsertDelay
                simulatedCursorPos = edit.position + newText.count

            default:
                break
            }
        }

        return totalTime
    }

    /// Executes edits sequentially using backwards editing (right-to-left)
    private func executeNextEditBackwards() {
        guard state == .editing else { return }
        guard currentEditIndex < positionedEdits.count else {
            finishEditing()
            return
        }

        // CRITICAL: Check focus BEFORE each editing operation
        // This ensures we NEVER edit in the wrong window
        if !isTargetWindowFocused() {
            let currentWindow = getFocusedWindowTitle()
            appLog("Focus check before edit - Target: '\(targetWindowTitle ?? "none")' Current: '\(currentWindow ?? "none")'", level: .debug)
            appLog("Not in target window, aborting editing", level: .debug)
            abortEditingWithError(.focusLostDuringEdit)
            return
        }

        let edit = positionedEdits[currentEditIndex]
        appLog("Executing edit \(currentEditIndex + 1)/\(positionedEdits.count) - cursor: \(actualCursorPosition), target: \(edit.position)", level: .debug)

        // Navigate to the edit position and execute it
        navigateAndExecuteEdit(edit)
    }

    /// Navigates to the edit position and executes it
    /// Key insight: For right-to-left editing, draft1 positions < current edit position are unchanged
    /// Always uses relative navigation (left arrows) to work correctly with pre-existing document content
    private func navigateAndExecuteEdit(_ edit: EditWithPosition) {
        let targetPosition = edit.position
        let leftMoveCount = actualCursorPosition - targetPosition

        if leftMoveCount > 0 {
            appLog("Moving left: \(leftMoveCount) characters", level: .debug)
            navigateLeftAndExecute(count: leftMoveCount, edit: edit)
        } else {
            // Already at the position - still pause before edit
            let preEditDelay = 0.2 * editingDelayMultiplier
            DispatchQueue.main.asyncAfter(deadline: .now() + preEditDelay) { [weak self] in
                guard let self = self, self.state == .editing else { return }
                self.executeEditAtCurrentPosition(edit)
            }
        }
    }

    /// Navigate left by arrow keys
    private func navigateLeftAndExecute(count: Int, edit: EditWithPosition) {
        let navigationDelay = 0.08 * editingDelayMultiplier
        sendKeysWithDelay(count: count, delay: navigationDelay) {
            self.sendArrowKey(.left)
        } completion: { [weak self] in
            guard let self = self, self.state == .editing else { return }

            // Short pause after navigation before editing
            let postNavigationDelay = 0.3 * self.editingDelayMultiplier
            DispatchQueue.main.asyncAfter(deadline: .now() + postNavigationDelay) { [weak self] in
                guard let self = self, self.state == .editing else { return }
                self.executeEditAtCurrentPosition(edit)
            }
        }
    }

    /// Executes a single edit operation (delete, insert, or replace) at the current cursor position
    /// Updates actualCursorPosition based on the operation performed
    private func executeEditAtCurrentPosition(_ edit: EditWithPosition) {
        let targetPosition = edit.position

        switch edit.operation {
        case .delete(let count):
            appLog("Deleting \(count) characters with forward delete", level: .debug)
            // Delete characters one at a time using forward delete (simpler, more reliable)
            let deleteDelay = 0.1 * editingDelayMultiplier
            sendKeysWithDelay(count: count, delay: deleteDelay) {
                self.sendForwardDelete()
            } completion: { [weak self] in
                guard let self = self, self.state == .editing else { return }

                // After deleting, cursor stays at targetPosition
                self.actualCursorPosition = targetPosition
                appLog("Deleted \(count) chars, cursor now at \(self.actualCursorPosition)", level: .debug)

                // Short pause after deletion
                let postDeleteDelay = 0.3 * self.editingDelayMultiplier
                DispatchQueue.main.asyncAfter(deadline: .now() + postDeleteDelay) { [weak self] in
                    guard let self = self, self.state == .editing else { return }
                    self.completeCurrentEditBackwards()
                }
            }

        case .insert(let text):
            appLog("Inserting '\(text.prefix(20))\(text.count > 20 ? "..." : "")'", level: .debug)
            let baseDelay = max(0.05, interCharacterDelay)
            let delay = baseDelay * editingDelayMultiplier
            sendCharactersWithDelay(text, delay: delay) { [weak self] in
                guard let self = self, self.state == .editing else { return }

                // After insertion, cursor is at targetPosition + inserted text length
                // NO move-back needed! We track actual position for next navigation
                self.actualCursorPosition = targetPosition + text.count
                appLog("Inserted \(text.count) chars, cursor now at \(self.actualCursorPosition)", level: .debug)

                // Longer pause after insert to let web editors catch up
                let postInsertDelay = 0.3 * self.editingDelayMultiplier
                DispatchQueue.main.asyncAfter(deadline: .now() + postInsertDelay) { [weak self] in
                    guard let self = self, self.state == .editing else { return }
                    self.completeCurrentEditBackwards()
                }
            }

        case .replace(let oldCount, let newText):
            appLog("Replacing \(oldCount) chars with '\(newText.prefix(30))\(newText.count > 30 ? "..." : "")'", level: .debug)
            executeReplace(oldCount: oldCount, newText: newText) { [weak self] in
                guard let self = self, self.state == .editing else { return }

                // After replace, cursor is at targetPosition + new text length
                // NO move-back needed!
                self.actualCursorPosition = targetPosition + newText.count
                appLog("Replaced \(oldCount) with \(newText.count) chars, cursor now at \(self.actualCursorPosition)", level: .debug)

                // Longer pause after replace to let web editors catch up
                let postReplaceDelay = 0.3 * self.editingDelayMultiplier
                DispatchQueue.main.asyncAfter(deadline: .now() + postReplaceDelay) { [weak self] in
                    guard let self = self, self.state == .editing else { return }
                    self.completeCurrentEditBackwards()
                }
            }

        default:
            // Other operations not used in backwards editing
            completeCurrentEditBackwards()
        }
    }

    /// Executes an atomic replace operation: delete the old text first, then insert the new text.
    /// This is the standard replace behavior - select/delete old content, then type new content.
    private func executeReplace(oldCount: Int, newText: String, completion: @escaping () -> Void) {
        let deleteDelay = 0.1 * editingDelayMultiplier
        let postDeleteDelay = 0.3 * editingDelayMultiplier
        let postInsertDelay = 0.3 * editingDelayMultiplier
        let baseDelay = max(0.05, interCharacterDelay) * editingDelayMultiplier

        // Insert the new text AFTER deleting the old text.
        let performInsert: () -> Void = { [weak self] in
            guard let self = self else { return }

            guard !newText.isEmpty else {
                completion()
                return
            }

            self.sendCharactersWithDelay(newText, delay: baseDelay) { [weak self] in
                guard let self = self, self.state == .editing else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + postInsertDelay) { [weak self] in
                    guard let self = self, self.state == .editing else { return }
                    completion()
                }
            }
        }

        // Delete first, then insert the new content.
        if oldCount > 0 {
            self.sendKeysWithDelay(count: oldCount, delay: deleteDelay) {
                self.sendForwardDelete()
            } completion: { [weak self] in
                guard let self = self, self.state == .editing else { return }

                DispatchQueue.main.asyncAfter(deadline: .now() + postDeleteDelay) { [weak self] in
                    guard let self = self, self.state == .editing else { return }
                    performInsert()
                }
            }
        } else {
            performInsert()
        }
    }

    /// Completes the current edit and moves to the next one
    private func completeCurrentEditBackwards() {
        currentEditIndex += 1

        // Update progress
        let progress = Double(currentEditIndex) / Double(positionedEdits.count)
        DispatchQueue.main.async {
            self.progressFraction = 0.5 + (progress * 0.5)
        }

        // Apply extra delay for custom editing duration, then move to next edit
        if extraDelayPerEdit > 0 {
            // Show thinking indicator during extra delay
            DispatchQueue.main.async {
                self.isThinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + extraDelayPerEdit) { [weak self] in
                guard let self = self, self.state == .editing else { return }
                DispatchQueue.main.async {
                    self.isThinking = false
                }
                self.executeNextEditBackwards()
            }
        } else {
            executeNextEditBackwards()
        }
    }

    private func sendKeysWithDelay(count: Int, delay: TimeInterval, keyAction: @escaping () -> Void, completion: @escaping () -> Void) {
        var remaining = count

        func sendNext() {
            // Stop immediately if user cancelled
            guard self.state == .typing || self.state == .editing else { return }

            guard remaining > 0 else {
                completion()
                return
            }

            keyAction()
            remaining -= 1

            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard self != nil else { return }
                    sendNext()
                }
            } else {
                // Add delay after last key to let web editors process it
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard self != nil else { return }
                    completion()
                }
            }
        }

        sendNext()
    }

    /// Starts typing characters for an edit operation using the same mechanism as the typing phase.
    /// This ensures reliable character delivery to web editors like Google Docs.
    private func sendCharactersWithDelay(_ text: String, delay: TimeInterval, completion: @escaping () -> Void) {
        guard !text.isEmpty else {
            completion()
            return
        }

        // Initialize edit character typing state (mirrors typing phase)
        editCharsToType = Array(text)
        editCharIndex = 0
        editCharCompletion = completion
        editCharPreviousChar = nil

        // Start typing using the same scheduling mechanism as typing phase
        scheduleNextEditChar(after: 0) // Start immediately
    }

    /// Schedules the next edit character - mirrors scheduleNextCharacter from typing phase
    private func scheduleNextEditChar(after delay: TimeInterval) {
        guard editCharIndex < editCharsToType.count else {
            // All characters typed - call completion after a final delay
            let finalDelay = interCharacterDelay * editingDelayMultiplier
            DispatchQueue.main.asyncAfter(deadline: .now() + finalDelay) { [weak self] in
                guard let self = self else { return }
                self.editCharCompletion?()
                self.editCharCompletion = nil
            }
            return
        }

        // Cancel any existing work item (mirrors typing phase)
        editCharWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.typeNextEditChar()
        }

        editCharWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Types the next edit character - mirrors typeNextCharacter from typing phase
    private func typeNextEditChar() {
        // Stop if user cancelled
        guard state == .editing else { return }

        guard editCharIndex < editCharsToType.count else {
            editCharCompletion?()
            editCharCompletion = nil
            return
        }

        // CRITICAL: Check focus BEFORE typing each character during editing
        // This ensures we NEVER type even a single character in the wrong window
        if !isTargetWindowFocused() {
            let currentWindow = getFocusedWindowTitle()
            appLog("Focus check before edit char - Target: '\(targetWindowTitle ?? "none")' Current: '\(currentWindow ?? "none")'", level: .debug)
            appLog("Not in target window, aborting editing", level: .debug)
            abortEditingWithError(.focusLostDuringEdit)
            return
        }

        let character = editCharsToType[editCharIndex]
        let charIndex = editCharIndex
        editCharIndex += 1

        // Log each character being sent (verbose level - very frequent)
        let unicodeValue = character.unicodeScalars.first?.value ?? 0
        appLog("Edit char[\(charIndex)]: '\(character)' (U+\(String(format: "%04X", unicodeValue)))", level: .verbose)

        // Send the character (same as typing phase)
        sendCharacter(character)

        // Temporarily set previousCharacter to editCharPreviousChar so extraDelay() uses the correct context
        let savedPreviousChar = previousCharacter
        previousCharacter = editCharPreviousChar

        // Calculate delay using the same extraDelay logic as typing phase
        let baseDelay = max(0.05, interCharacterDelay)
        let extra = extraDelay(afterTyping: character)
        let nextDelay = (baseDelay + extra) * editingDelayMultiplier

        // Restore typing phase's previousCharacter and update edit phase's
        previousCharacter = savedPreviousChar
        editCharPreviousChar = character

        // Schedule next character (mirrors typing phase)
        scheduleNextEditChar(after: nextDelay)
    }

    private func pauseEditing() {
        guard state == .editing else { return }

        // Record what state we're pausing from (for correct resume)
        stateBeforePause = .editing

        typingWorkItem?.cancel()
        typingWorkItem = nil

        // Also cancel edit character typing work item
        editCharWorkItem?.cancel()
        editCharWorkItem = nil
        editCharCompletion = nil

        stopPeriodicFocusCheck()

        DispatchQueue.main.async {
            self.state = .paused
            self.isThinking = false
            self.progressText = "Paused. Switch back to your document to resume."
        }
    }

    private func resumeEditing() {
        guard state == .paused else { return }

        DispatchQueue.main.async {
            self.state = .editing
            self.progressText = "Resumed editing…"
            self.isThinking = false
        }

        // Restart periodic focus check
        startPeriodicFocusCheck()

        executeNextEditBackwards()
    }

    private func finishEditing() {
        typingWorkItem?.cancel()
        typingWorkItem = nil

        stopPeriodicFocusCheck()
        endSleepPrevention()

        DispatchQueue.main.async {
            // Record editing phase duration
            if let editStart = self.editingStartDate {
                self.lastEditingPhaseDuration = Date().timeIntervalSince(editStart)
            }

            // Total run duration (typing + editing)
            if let start = self.typingStartDate {
                self.lastRunDuration = Date().timeIntervalSince(start)
            }

            self.progressFraction = 1.0
            self.state = .idle
            self.lastCompletionDate = Date()
            self.progressText = "Editing complete."
            self.isThinking = false
            self.targetAppPID = nil
            self.targetWindowTitle = nil
            self.editingStartDate = nil

            // Clear editing state
            self.draft2Text = nil
            self.positionedEdits = []
            self.currentEditIndex = 0
            self.actualCursorPosition = 0
            self.customEditingDuration = nil
            self.extraDelayPerEdit = 0
        }
    }

    /// Aborts editing with a typed error
    private func abortEditingWithError(_ error: EditingError) {
        typingWorkItem?.cancel()
        typingWorkItem = nil

        // Cancel edit character typing work item
        editCharWorkItem?.cancel()
        editCharWorkItem = nil
        editCharCompletion = nil

        stopPeriodicFocusCheck()
        endSleepPrevention()

        appLog("Editing aborted: \(error.localizedDescription)", level: .error)

        DispatchQueue.main.async {
            self.state = .idle
            self.isThinking = false
            self.progressText = "Editing aborted. Use Cmd+Z to undo changes."
            self.progressFraction = Double(self.currentEditIndex) / Double(max(1, self.positionedEdits.count))
            self.lastEditingError = error
            self.targetAppPID = nil
            self.targetWindowTitle = nil

            // Clear editing state
            self.draft2Text = nil
            self.positionedEdits = []
            self.currentEditIndex = 0
            self.actualCursorPosition = 0
            self.customEditingDuration = nil
            self.extraDelayPerEdit = 0
        }
    }

    // MARK: - ESC Key Handling

    /// Sets up an event tap to detect ESC key presses
    private func setupEscEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            // 53 is the keycode for ESC on macOS
            if keycode == 53,
               let userInfo = userInfo {
                let manager = Unmanaged<TypingManager>.fromOpaque(userInfo).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.handleEscPressed()
                }
            }

            return Unmanaged.passUnretained(event)
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        ) else {
            return
        }

        escEventTap = tap
        escRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = escRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handleEscPressed() {
        // During typing: pause (can resume)
        // During editing: stop completely
        if state == .typing {
            pauseTyping()
        } else if state == .editing {
            // Stop editing completely - no resume option
            stopTyping()
        }
    }
}
