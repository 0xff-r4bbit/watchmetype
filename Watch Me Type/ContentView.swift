import SwiftUI

enum DurationUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minutes: return "Minutes"
        case .hours: return "Hours"
        }
    }
}

struct ContentView: View {
    @State private var inputText: String = ""
    @State private var targetWPM: Double = 80
    @State private var removeBlankLines: Bool = false
    @State private var removeEmojis: Bool = false
    @State private var removeHorizontalRules: Bool = false
    @State private var removeBulletPoints: Bool = false
    @State private var replaceEmDashesWithCommas: Bool = false
    @State private var showStartConfirmation: Bool = false
    @State private var highlightEstimate: Bool = false

    // Optional total duration
    @State private var desiredDurationValue: String = ""
    @State private var durationUnit: DurationUnit = .minutes

    @StateObject private var typingManager = TypingManager()

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Watch Me Type")
                    .font(.largeTitle)
                    .bold()

                Text("Paste or type the text you want typed automatically, set a target WPM or total time, then click Start and switch to your document.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Text to type:")
                    .font(.headline)

                HStack(alignment: .top, spacing: 16) {
                    TextEditor(text: $inputText)
                        .frame(minHeight: 220)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3))
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pre-processing")
                            .font(.subheadline)
                            .bold()

                        Toggle("Remove blank lines", isOn: $removeBlankLines)
                        Toggle("Remove emojis", isOn: $removeEmojis)
                        Toggle("Remove horizontal rules", isOn: $removeHorizontalRules)
                        Toggle("Remove bullet points (- ...)", isOn: $removeBulletPoints)
                        Toggle("Replace em-dashes with commas", isOn: $replaceEmDashesWithCommas)

                        Spacer()

                        Button("Process") {
                            processInputText()
                        }
                        .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .frame(width: 260, alignment: .topLeading)
                }

                // WPM + labels
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target WPM: \(Int(targetWPM))")
                        .font(.subheadline)

                    HStack {
                        Slider(value: $targetWPM, in: 40...120, step: 10)
                        Spacer()
                    }

                    // Informal “average speed” labels
                    HStack {
                        Text("🐌")
                        Spacer()
                        Text("🚶‍♂️‍➡️")
                        Spacer()
                        Text("🏃‍♂️‍➡️")
                    }
                }

                // Estimated time + optional total duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        estimatedTimeText
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Or, you can set a desired typing duration:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("e.g. 10", text: $desiredDurationValue)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)

                        Picker("", selection: $durationUnit) {
                            ForEach(DurationUnit.allCases) { unit in
                                Text(unit.displayName).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 180)

                        if let summary = desiredDurationSummary {
                            Text(summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                }

                HStack(spacing: 12) {
                    Button("Start") {
                        showStartConfirmation = true
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Stop") {
                        typingManager.stopTyping()
                    }

                    Spacer()
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 750, minHeight: 540)

            if typingManager.state != .idle || typingManager.lastCompletionDate != nil {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    if typingManager.state == .idle, typingManager.lastCompletionDate != nil {
                        Text("🎉 Done! 🎉")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)

                        if let subtitle = completionSubtitle {
                            Text(subtitle)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        Button("Let's go again.") {
                            typingManager.stopTyping()
                            inputText = ""
                            desiredDurationValue = ""
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(statusText)
                            .font(.title2)
                            .bold()
                            .foregroundColor(.white)

                        if !typingManager.progressText.isEmpty {
                            Text(typingManager.progressText)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Show progress bar when a run is active, paused, or counting down.
                        if typingManager.state == .typing
                            || typingManager.state == .paused
                            || typingManager.state == .countingDown {

                            VStack(spacing: 6) {
                                ProgressView(value: typingManager.progressFraction)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 320)

                                Text("\(Int(typingManager.progressFraction * 100))% complete")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            .padding(.horizontal)
                        }

                        if typingManager.state == .paused {
                            HStack(spacing: 16) {
                                Button("Resume") {
                                    typingManager.resumeWithCountdown()
                                }

                                Button("Stop") {
                                    typingManager.stopTyping()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Stop") {
                                typingManager.stopTyping()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding()
            }
        }
        .onChange(of: targetWPM) {
            flashEstimate()
        }
        .alert("Get ready to start typing", isPresented: $showStartConfirmation) {
            Button("Cancel", role: .cancel) {
                // Just close the alert and return to the main screen
            }

            Button("Confirm") {
                typingManager.startTyping(
                    text: inputText,
                    wpm: Int(targetWPM),
                    countdown: 10,
                    totalDurationSeconds: desiredDurationSeconds,
                    simulateMistakes: true
                )
            }
        } message: {
            Text("""
Once you press Confirm, you will have 10 seconds to switch to the window where you want the text to be typed.

After that, the app will begin typing automatically. For best results, avoid touching your keyboard or mouse until it is finished.

You can press Esc at any time to pause typing. When paused, use the Resume button in this window; a short countdown will give you time to switch back to your document before typing continues.

Typing will pause automatically if you change apps. You can click Stop in this window to cancel at any time.
""")
        }
    }

    private func flashEstimate() {
        withAnimation(.easeInOut(duration: 0.2)) {
            highlightEstimate = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                highlightEstimate = false
            }
        }
    }

    private var statusText: String {
        switch typingManager.state {
        case .idle:
            return "Idle"
        case .countingDown:
            if typingManager.countdownRemaining > 0 {
                return "Starting in \(typingManager.countdownRemaining) seconds…"
            } else {
                return "Preparing to start…"
            }
        case .typing:
            return typingManager.isThinking ? "🤔 Thinking…" : "⌨️ Typing…"
        case .paused:
            return "Paused"
        }
    }

    private var estimatedTimeText: Text {
        guard let minutes = estimatedMinutes else {
            return Text("Estimated: at least —.")
                .foregroundColor(.secondary)
        }

        let unit = minutes == 1 ? "minute" : "minutes"

        let prefix = Text("Estimated: at least ")
            .foregroundColor(.secondary)

        let number = Text("\(minutes)")
            .bold()
            .foregroundColor(highlightEstimate ? .accentColor : .primary)

        let suffix = Text(" \(unit).")
            .foregroundColor(.secondary)

        return prefix + number + suffix
    }

    private var estimatedMinutes: Int? {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let characterCount = trimmed.count

        guard characterCount > 0 else {
            return nil
        }

        // Match TypingManager: derive base typing time from WPM and character count,
        // then add an equal amount of jitter (thinking pauses, commas, mistakes, etc.).
        let wpm = max(1.0, targetWPM)
        let charsPerMinute = max(5.0, wpm * 5.0)
        let interCharacterDelay = 60.0 / charsPerMinute

        let baseTypingTimeSeconds = Double(characterCount) * interCharacterDelay

        let jitterMultiplier = 1.0
        let estimatedJitterSeconds = baseTypingTimeSeconds * jitterMultiplier
        let totalSeconds = baseTypingTimeSeconds + estimatedJitterSeconds

        let minutes = totalSeconds / 60.0
        let roundedMinutes = max(1, Int(round(minutes)))
        return roundedMinutes
    }

    private var desiredDurationSummary: String? {
        guard let seconds = desiredDurationSeconds, seconds > 0 else {
            return nil
        }

        switch durationUnit {
        case .minutes:
            let value = seconds / 60.0
            let rounded = Int(round(value))
            let unit = rounded == 1 ? "minute" : "minutes"
            return "~\(rounded) \(unit)"
        case .hours:
            let value = seconds / 3600.0
            let rounded = Int(round(value))
            let unit = rounded == 1 ? "hour" : "hours"
            return "~\(rounded) \(unit)"
        }
    }

    private var completionSubtitle: String? {
        guard typingManager.state == .idle,
              let completionDate = typingManager.lastCompletionDate else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let timeString = formatter.string(from: completionDate)

        if let duration = typingManager.lastRunDuration {
            let totalSeconds = Int(duration.rounded())
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60

            if minutes > 0 {
                return "Completed at \(timeString) after running for \(minutes) minute(s) and \(seconds) second(s)."
            } else {
                return "Completed at \(timeString) after running for \(seconds) second(s)."
            }
        } else {
            return "Completed at \(timeString)"
        }
    }

    private var estimatedDurationDescription: String {
        guard let minutes = estimatedMinutes else {
            return "—"
        }
        return "\(minutes) minute(s)"
    }

    private var desiredDurationSeconds: TimeInterval? {
        guard
            let value = Double(desiredDurationValue.replacingOccurrences(of: ",", with: ".")),
            value > 0
        else {
            return nil
        }

        switch durationUnit {
        case .minutes:
            return value * 60
        case .hours:
            return value * 3600
        }
    }
    private func processInputText() {
        var text = inputText

        if removeBlankLines || removeHorizontalRules || removeBulletPoints {
            let lines = text.components(separatedBy: .newlines)
            var newLines: [String] = []

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if removeBlankLines && trimmed.isEmpty {
                    continue
                }

                if removeHorizontalRules && isHorizontalRule(trimmed) {
                    continue
                }

                var processedLine = line

                if removeBulletPoints {
                    processedLine = stripLeadingBullet(from: processedLine)
                }

                newLines.append(processedLine)
            }

            text = newLines.joined(separator: "\n")
        }

        if removeEmojis {
            text = String(text.filter { !$0.isEmojiCharacter })
        }

        if replaceEmDashesWithCommas {
            text = replacingEmDashesWithCommas(in: text)
        }

        // Collapse multiple spaces into single spaces.
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }

        // Remove stray spaces immediately before common punctuation.
        let punctuations = [",", ".", "!", "?", ":", ";"]
        for p in punctuations {
            let bad = " " + p
            while text.contains(bad) {
                text = text.replacingOccurrences(of: bad, with: p)
            }
        }

        inputText = text
    }
}

#Preview {
    ContentView()
}

private extension Character {
    var isEmojiCharacter: Bool {
        // Never treat standard digits as emoji, even if they have emoji-style variants.
        if self.isNumber {
            return false
        }

        return unicodeScalars.contains { scalar in
            scalar.properties.isEmoji || scalar.properties.isEmojiPresentation
        }
    }
}

private func isHorizontalRule(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return false }

    let allowed = CharacterSet(charactersIn: "-_*—– ⸻")
    return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
}

private func applySpellingNoise(to text: String) -> String {
    var result = ""
    var currentWord = ""
    var wordCount = 0
    var nextMistakeAt = Int.random(in: 8...12)

    func flushWord() {
        guard !currentWord.isEmpty else { return }

        wordCount += 1
        var mutated = currentWord

        if wordCount >= nextMistakeAt {
            if let index = mutated.indices.filter({ mutated[$0].isLetter }).randomElement() {
                let original = mutated[index]
                let replacement = randomNearbyLetter(matchingCaseOf: original)
                mutated.replaceSubrange(index...index, with: [replacement])
            }
            wordCount = 0
            nextMistakeAt = Int.random(in: 8...12)
        }

        result += mutated
        currentWord = ""
    }

    for ch in text {
        if ch.isLetter {
            currentWord.append(ch)
        } else {
            flushWord()
            result.append(ch)
        }
    }
    flushWord()

    return result
}

private func randomNearbyLetter(matchingCaseOf character: Character) -> Character {
    let isUpper = character.isUppercase
    let letters = Array("abcdefghijklmnopqrstuvwxyz")
    let lower = Character(character.lowercased())
    guard let index = letters.firstIndex(of: lower) else {
        return character
    }

    let offsets = [-2, -1, 1, 2].shuffled()
    for offset in offsets {
        let newIndex = index + offset
        if newIndex >= 0 && newIndex < letters.count {
            let newChar = letters[newIndex]
            return isUpper ? Character(String(newChar).uppercased()) : newChar
        }
    }
    return character
}

private func replacingEmDashesWithCommas(in text: String) -> String {
    var result = ""
    var index = text.startIndex

    while index < text.endIndex {
        let ch = text[index]

        if ch == "—" {
            // Replace em-dash with a comma, ensuring a following space.
            result.append(",")
            let nextIndex = text.index(after: index)
            if nextIndex < text.endIndex {
                let nextChar = text[nextIndex]
                if nextChar != " " {
                    result.append(" ")
                }
            }
            index = text.index(after: index)
        } else {
            result.append(ch)
            index = text.index(after: index)
        }
    }

    return result
}
private func stripLeadingBullet(from line: String) -> String {
    // Remove simple bullet markers like "- " or " - " at the start of a line,
    // optionally preceded by whitespace.
    var index = line.startIndex

    // Skip initial whitespace
    while index < line.endIndex, line[index].isWhitespace {
        index = line.index(after: index)
    }

    // Now look for "- " or " - " patterns
    if index < line.endIndex, line[index] == "-" {
        let afterDash = line.index(after: index)
        if afterDash < line.endIndex, line[afterDash] == " " {
            // Pattern "- "
            let contentStart = line.index(after: afterDash)
            return String(line[contentStart...])
        }
    } else if index < line.endIndex, line[index] == "•" {
        // Handle bullet character like "• "
        let afterBullet = line.index(after: index)
        if afterBullet < line.endIndex, line[afterBullet] == " " {
            let contentStart = line.index(after: afterBullet)
            return String(line[contentStart...])
        }
    }

    // Also handle " - " pattern (space, dash, space) after indentation
    // by scanning again from the first non-space position.
    let trimmedLeading = line.trimmingCharacters(in: .whitespaces)
    if trimmedLeading.hasPrefix("- ") {
        let dropCount = line.count - trimmedLeading.count + 2
        let contentStart = line.index(line.startIndex, offsetBy: dropCount)
        return String(line[contentStart...])
    }

    return line
}