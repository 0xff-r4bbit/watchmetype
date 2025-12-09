import Foundation
import Combine
import ApplicationServices
import AppKit

final class TypingManager: NSObject, ObservableObject {
    enum TypingState {
        case idle
        case countingDown
        case typing
        case paused
    }
    
    @Published var state: TypingState = .idle
    @Published var countdownRemaining: Int = 0
    @Published var progressText: String = ""
    @Published var isThinking: Bool = false
    @Published var lastCompletionDate: Date?
    @Published var lastRunDuration: TimeInterval?
    @Published var progressFraction: Double = 0.0  // 0.0 = not started, 1.0 = complete
    
    private var countdownTimer: Timer?
    private var typingStartDate: Date?
    
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
    
    // Focus tracking
    private var targetAppPID: pid_t?

    // Global Esc key handling
    private var escEventTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?
    
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
        
        state = .idle
        countdownRemaining = 0
        progressText = ""
        isThinking = false
        targetAppPID = nil
        lastCompletionDate = nil
        progressFraction = 0.0
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

        // At the moment typing begins, record the current frontmost app
        // as the intended typing target.
        targetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        state = .typing
        progressText = "Typing in progress…"
        isThinking = false

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
        
        // Safety check: if the user has switched away from the target app,
        // pause typing instead of sending characters into the wrong window.
        if !isTargetAppFrontmost() {
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
        }
    }
    
    // MARK: - Pause / resume on app focus changes
    
    @objc private func handleActiveAppChange(_ notification: Notification) {
        guard let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        let newPID = runningApp.processIdentifier
        
        guard let targetPID = targetAppPID else {
            return
        }
        
        switch state {
        case .typing:
            // If we leave the target app, pause.
            if newPID != targetPID {
                pauseTyping()
            }
        case .paused:
            // If we come back to the target app, resume.
            if newPID == targetPID {
                resumeTyping()
            }
        default:
            break
        }
    }
    
    private func pauseTyping() {
        guard state == .typing else { return }
        
        typingWorkItem?.cancel()
        typingWorkItem = nil
        
        DispatchQueue.main.async {
            self.state = .paused
            self.isThinking = false
            self.progressText = "Paused. Press Resume to continue typing."
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

        scheduleNextCharacter(after: interCharacterDelay)
    }

    // Resume with a short countdown (for user-initiated Resume)
    func resumeWithCountdown(_ seconds: Int = 5) {
        guard state == .paused else { return }

        countdownTimer?.invalidate()
        countdownRemaining = seconds
        state = .countingDown
        progressText = "Resuming in \(seconds) seconds… Switch back to your document."

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            DispatchQueue.main.async {
                if self.countdownRemaining > 0 {
                    self.countdownRemaining -= 1
                    self.progressText = "Resuming in \(self.countdownRemaining) seconds… Switch back to your document."
                } else {
                    timer.invalidate()
                    self.beginTypingLoop()
                }
            }
        }
    }
    
    private func isTargetAppFrontmost() -> Bool {
        guard let targetPID = targetAppPID else {
            // If we don't have a recorded target app, allow typing.
            return true
        }
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return true
        }
        return frontmostPID == targetPID
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
        
        // Special-case newlines: send a real Return key event so apps treat it
        // exactly like pressing the Enter/Return key, instead of a raw "\n".
        if character == "\n" || character == "\r" {
            let returnKeyCode: CGKeyCode = 0x24 // kVK_Return
            
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: returnKeyCode, keyDown: false) else {
                return
            }
            
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            return
        }
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }
        
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
            if !self.isTargetAppFrontmost() {
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
        let backspaceKeyCode: CGKeyCode = 0x33 // Delete key
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: backspaceKeyCode, keyDown: false) else {
            return
        }
        
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    // MARK: - Esc key handling

    private func setupEscEventTap() {
        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }

            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            // 53 is the keycode for Esc on macOS.
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
        // Only meaningful while actively typing.
        if state == .typing {
            pauseTyping()
        }
    }
}
