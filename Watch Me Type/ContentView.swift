import SwiftUI
import AppKit

enum DurationUnit: String, CaseIterable, Identifiable {
    case minutes
    case hours

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minutes:
            return "minutes"
        case .hours:
            return "hours"
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
    @State private var useTotalTime: Bool = false
    @State private var hasShownAccessibilityAlert: Bool = false
    @State private var storedNormalWindowFrame: CGRect? = nil
    @State private var isAdjustingWindowFrame: Bool = false
    private let compactOverlayWidth: CGFloat = 430

    @FocusState private var isInputFocused: Bool

    // Optional total duration
    @State private var desiredDurationValue: String = ""
    @State private var durationUnit: DurationUnit = .minutes

    // Two-draft editing mode
    @State private var inputTextDraft2: String = ""
    @State private var useEditingMode: Bool = false
    @State private var customEditingDuration: Bool = false
    @State private var editingDurationValue: String = ""
    @State private var editingDurationUnit: DurationUnit = .minutes

    // Error state for editing failures
    @State private var showEditingError: Bool = false
    @State private var editingErrorMessage: String = ""

    @StateObject private var typingManager = TypingManager()

    private var isOverlayVisible: Bool {
        typingManager.state != .idle || typingManager.lastCompletionDate != nil
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                // App header + support button
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Watch Me Type")
                            .font(.title)
                            .bold()

                        Text(.init("an [open-source](https://github.com/0xff-r4bbit/watchmetype) macOS app that mimics human typing"))
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    KoFiSupportButton()
                }

                HStack(alignment: .top, spacing: 16) {
                    // Conditional layout: Single draft vs Two drafts
                    if useEditingMode {
                        // Two-draft mode: Side-by-side editors
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Draft 1 (Starting Point)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $inputText)
                                        .focused($isInputFocused)
                                        .padding(8)
                                        .scrollIndicators(.hidden)

                                    if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Paste your first draft here.")
                                            .foregroundColor(.secondary)
                                            .padding(.top, 14)
                                            .padding(.leading, 12)
                                    }
                                }
                                .frame(minHeight: 260)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.3))
                                )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Draft 2 (Final Version)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $inputTextDraft2)
                                        .padding(8)
                                        .scrollIndicators(.hidden)

                                    if inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Paste your final draft here (optional).")
                                            .foregroundColor(.secondary)
                                            .padding(.top, 14)
                                            .padding(.leading, 12)
                                    }
                                }
                                .frame(minHeight: 260)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.3))
                                )
                            }
                        }
                    } else {
                        // Single-draft mode (current behavior)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $inputText)
                                .focused($isInputFocused)
                                .padding(8)
                                .scrollIndicators(.hidden)

                            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Paste the text you'd like to type here.")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 14)
                                    .padding(.leading, 12)
                            }
                        }
                        .frame(minHeight: 260)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                    }

                    // Right: settings column
                    VStack(alignment: .leading, spacing: 16) {
                        // Pre-processing card
                        VStack(alignment: .leading, spacing: 8) {
                            Text("􂺹  Clean-Up")
                                .font(.headline)
                                .bold()

                            Toggle("remove blank lines", isOn: $removeBlankLines)
                            Toggle("remove emojis", isOn: $removeEmojis)
                            Toggle("remove horizontal rules", isOn: $removeHorizontalRules)
                            Toggle("remove bullet points (- ...)", isOn: $removeBulletPoints)
                            Toggle("replace em-dashes with commas", isOn: $replaceEmDashesWithCommas)

                            Button("Process") {
                                processInputText()
                            }
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .padding(.top, 4)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .layoutPriority(1)

                        // Typing speed card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("􀐳 Typing Speed")
                                .font(.headline)
                                .bold()

                            // Target speed slider + labels
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Target Speed: \(Int(targetWPM)) WPM")
                                    .font(.subheadline)

                                Slider(value: $targetWPM, in: 40...120, step: 10)

                                HStack {
                                    Text("􀓐")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("average")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("􀓎")
                                        .font(.subheadline)
                                }
                            }

                            Toggle("Custom Typing Duration", isOn: $useTotalTime)
                                .font(.subheadline)

                            // Estimated time or total duration
                            VStack(alignment: .leading, spacing: 6) {
                                if useTotalTime {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text("type for at least")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 4)

                                        TextField("e.g. 10", text: $desiredDurationValue)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)

                                        Picker("", selection: $durationUnit) {
                                            ForEach(DurationUnit.allCases) { unit in
                                                Text(unit.displayName).tag(unit)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: .infinity)
                                    }
                                } else {
                                    estimatedTimeText
                                        .font(.subheadline)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .layoutPriority(1)

                        // Two-draft editing mode card
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 8) {
                                Toggle("Enable", isOn: $useEditingMode)
                                    .font(.subheadline)

                                Text("Editing Mode")
                                    .font(.headline)
                                    .bold()

                                Spacer()
                            }

                            if useEditingMode {
                                Text("Type Draft 1, then edit it into Draft 2")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Toggle("Custom Editing Duration", isOn: $customEditingDuration)
                                    .font(.subheadline)
                                    .padding(.top, 4)

                                if customEditingDuration {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text("edit for at least")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .padding(.vertical, 4)

                                        TextField("e.g. 5", text: $editingDurationValue)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)

                                        Picker("", selection: $editingDurationUnit) {
                                            ForEach(DurationUnit.allCases) { unit in
                                                Text(unit.displayName).tag(unit)
                                            }
                                        }
                                        .pickerStyle(.segmented)
                                        .frame(maxWidth: .infinity)
                                    }
                                }

                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .layoutPriority(1)

                        HStack {
                            Spacer()
                            Button("Start") {
                                showStartConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.top, 8)
                    }
                    .frame(width: 320, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxHeight: .infinity, alignment: .top)

            }
            .padding()
            .frame(
                minWidth: isOverlayVisible ? compactOverlayWidth : (useEditingMode ? 1000 : 750),
                minHeight: useEditingMode ? 700 : 600
            )
            .allowsHitTesting(!isOverlayVisible)

            if isOverlayVisible {
                BlurOverlay()
                    .ignoresSafeArea()
                    .overlay(
                        Color.black.opacity(0.7)
                            .ignoresSafeArea()
                    )
                    // Capture pointer events across the whole window so underlying onHover doesn’t fire.
                    .contentShape(Rectangle())
                    .onTapGesture { }

                VStack(spacing: 12) {
                    if typingManager.state == .idle, typingManager.lastCompletionDate != nil {
                        Text("🎉 Done! 🎉")
                            .font(.title)
                            .bold()
                            .foregroundColor(.white)

                        if let subtitle = completionSubtitle {
                            Text(subtitle)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }

                        // Social follow CTA + icons
                        VStack(spacing: 16) {
                            Text("If this helped you, please consider following me for future updates.")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)

                            HStack(spacing: 16) {
                                Button {
                                    if let url = URL(string: "https://ko-fi.com/0xffr4bbit") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_ko-fi")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                                .hoverPointer()

                                Button {
                                    if let url = URL(string: "https://buymeacoffee.com/0xff.r4bbit") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_buymeacoffee")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                                .hoverPointer()

                                Button {
                                    if let url = URL(string: "https://x.com/0xff_r4bbit") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_x")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                                .hoverPointer()

                                Button {
                                    if let url = URL(string: "https://www.reddit.com/user/0xff-r4bbit/") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_reddit")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 32, height: 32)
                                }
                                .hoverPointer()

                                Button {
                                    if let url = URL(string: "https://www.instagram.com/0xff.r4bbit/") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_instagram")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                                .hoverPointer()

                                Button {
                                    if let url = URL(string: "https://bsky.app/profile/0xff-r4bbit.bsky.social") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_bluesky")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                                .hoverPointer()

                                Button {
                                    if let url = URL(string: "https://mastodon.social/@0xff_r4bbit") {
                                        NSWorkspace.shared.open(url)
                                    }
                                } label: {
                                    Image("socials_mastodon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 36, height: 36)
                                }
                                .hoverPointer()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 10)

                        Button("Let's go again.") {
                            typingManager.stopTyping()
                            restoreNormalWindowFrame()
                        }
                        .padding(.top, 14)
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text(statusText)
                            .font(.title)
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
        .onAppear {
            handleAccessibilityOnAppear()
        }
        .onChange(of: targetWPM) { _, _ in
            flashEstimate()
        }
        .onChange(of: isOverlayVisible) { _, newValue in
            // When the overlay disappears entirely, ensure we return to a normal window.
            if !newValue {
                DispatchQueue.main.async {
                    setWindowAlwaysOnTop(false)
                    restoreNormalWindowFrame()
                }
            }
        }
        .onChange(of: typingManager.state) { _, newState in
            DispatchQueue.main.async {
                let isRunActive = newState != .idle
                setWindowAlwaysOnTop(isRunActive)

                if isRunActive {
                    compactWindowForOverlay()
                } else {
                    // Typing finished (Done overlay may still be visible): return to normal size + window level.
                    restoreNormalWindowFrame()
                }
            }
        }
        .onChange(of: useEditingMode) { _, _ in
            // When toggling editing mode, reposition window to stay on screen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                adjustWindowPositionForEditingMode()
            }
        }
        .onChange(of: typingManager.progressText) { _, newText in
            if newText.contains("aborted due to verification failure") {
                editingErrorMessage = """
                Cursor position verification failed during editing.

                This usually happens when:
                • The document was modified externally
                • The cursor was moved manually
                • The application's text field behaves unexpectedly

                Please try again, and avoid interacting with the document during editing.
                """
                showEditingError = true
            }
        }
        .alert("Get ready to start typing!", isPresented: $showStartConfirmation) {
            Button("Cancel", role: .cancel) {
                // Just close the alert and return to the main screen
            }

            Button("Confirm") {
                if useEditingMode && !inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Two-phase mode: type Draft 1, then edit to Draft 2
                    typingManager.startTwoPhaseTyping(
                        draft1: inputText,
                        draft2: inputTextDraft2,
                        wpm: Int(targetWPM),
                        countdown: 10,
                        typingDuration: desiredDurationSeconds,
                        editingDuration: editingDurationSeconds,
                        simulateMistakes: true
                    )
                } else {
                    // Single-draft mode (existing behavior)
                    typingManager.startTyping(
                        text: inputText,
                        wpm: Int(targetWPM),
                        countdown: 10,
                        totalDurationSeconds: desiredDurationSeconds,
                        simulateMistakes: true
                    )
                }
            }
        } message: {
            if useEditingMode && !inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("""
You'll have 10 seconds to switch windows.
Phase 1: Type Draft 1 completely
Phase 2: Edit Draft 1 into Draft 2
Press ESC to pause.
""")
            } else {
                Text("""
You'll have 10 seconds to switch to the window where the text will go.
To pause, press ESC or switch apps.
""")
            }
        }
        .alert("Editing Error", isPresented: $showEditingError) {
            Button("OK", role: .cancel) {
                typingManager.stopTyping()
            }
        } message: {
            Text(editingErrorMessage)
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
            let phaseIndicator = useEditingMode && !inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Phase 1: " : ""
            return typingManager.isThinking
                ? "\(phaseIndicator)🤔 Thinking 🤔"
                : "\(phaseIndicator)⌨️ Typing ⌨️"
        case .editing:
            return "Phase 2: ✏️ Editing ✏️"
        case .paused:
            return "⏸ Paused ⏸"
        }
    }

    private var estimatedTimeText: Text {
        guard let minutes = estimatedMinutes else {
            return Text("Est. at least —.")
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

    private var editingDurationSeconds: TimeInterval? {
        guard customEditingDuration,
              let value = Double(editingDurationValue.replacingOccurrences(of: ",", with: ".")),
              value > 0
        else {
            return nil
        }

        switch editingDurationUnit {
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

    private func handleAccessibilityOnAppear() {
        // Only run this once per launch so we don't nag if the view reloads.
        guard !hasShownAccessibilityAlert else { return }
        hasShownAccessibilityAlert = true

        // Move the window out of the way as soon as it actually exists on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Store the normal frame once (used to restore after the overlay compacts the window).
            storeNormalWindowFrameIfNeeded()

            moveWindowToRightEdge()

            // If we're not yet trusted, show our explanation alert.
            if !AccessibilityPermissionHelper.isTrusted {
                showAccessibilityPreflightAlert()
            }
        }
    }

    private func moveWindowToRightEdge() {
        guard
            let screen = NSScreen.main,
            let window = NSApp.mainWindow ?? NSApp.windows.first
        else {
            return
        }

        storeNormalWindowFrameIfNeeded()
        let screenFrame = screen.visibleFrame
        var windowFrame = window.frame

        // Position the window near the right edge, centred vertically.
        windowFrame.origin.x = screenFrame.maxX - windowFrame.size.width - 20
        windowFrame.origin.y = screenFrame.midY - windowFrame.size.height / 2

        window.setFrame(windowFrame, display: true, animate: true)
    }

    private func setWindowAlwaysOnTop(_ enabled: Bool) {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        window.level = enabled ? .statusBar : .normal
    }

    private func storeNormalWindowFrameIfNeeded() {
        guard storedNormalWindowFrame == nil else { return }
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        storedNormalWindowFrame = window.frame
    }

    private func compactWindowForOverlay() {
        storeNormalWindowFrameIfNeeded()

        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        var newFrame = window.frame
        newFrame.size.width = compactOverlayWidth

        // Keep the right edge aligned to the screen’s right edge (with a small margin).
        newFrame.origin.x = screenFrame.maxX - newFrame.size.width - 20

        // Keep the window vertically centred (same approach as `moveWindowToRightEdge`).
        newFrame.origin.y = screenFrame.midY - newFrame.size.height / 2

        // Defer window frame changes to avoid triggering AppKit layout recursion during SwiftUI updates.
        DispatchQueue.main.async {
            window.setFrame(newFrame, display: true, animate: false)

            // Correction pass: ensure alignment after SwiftUI may enforce a larger min width.
            DispatchQueue.main.async {
                guard !isAdjustingWindowFrame else { return }
                isAdjustingWindowFrame = true
                defer { isAdjustingWindowFrame = false }

                guard let screenFrame2 = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

                let current = window.frame
                let targetX = screenFrame2.maxX - current.size.width - 20
                let targetY = screenFrame2.midY - current.size.height / 2

                // If we're already effectively aligned, don't force another layout pass.
                if abs(current.origin.x - targetX) < 1 && abs(current.origin.y - targetY) < 1 {
                    return
                }

                var corrected = current
                corrected.origin.x = targetX
                corrected.origin.y = targetY
                window.setFrame(corrected, display: true, animate: false)
            }
        }
    }

    private func adjustWindowPositionForEditingMode() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        let currentFrame = window.frame
        var newFrame = currentFrame

        // If window extends past right edge, anchor it to the right edge
        if newFrame.maxX > screenFrame.maxX {
            newFrame.origin.x = screenFrame.maxX - newFrame.size.width - 20
        }

        // Ensure window stays within vertical bounds
        if newFrame.maxY > screenFrame.maxY {
            newFrame.origin.y = screenFrame.maxY - newFrame.size.height - 20
        }
        if newFrame.minY < screenFrame.minY {
            newFrame.origin.y = screenFrame.minY + 20
        }

        window.setFrame(newFrame, display: true, animate: true)
    }

    private func restoreNormalWindowFrame() {
        guard let normal = storedNormalWindowFrame else { return }
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            // Defer window frame changes to avoid triggering AppKit layout recursion during SwiftUI updates.
            DispatchQueue.main.async {
                window.setFrame(normal, display: true, animate: false)
            }
            return
        }

        var restored = normal
        // Re-align to the right edge of the *current* display in case the window moved screens.
        restored.origin.x = screenFrame.maxX - restored.size.width - 20
        restored.origin.y = screenFrame.midY - restored.size.height / 2

        // Defer window frame changes to avoid triggering AppKit layout recursion during SwiftUI updates.
        DispatchQueue.main.async {
            window.setFrame(restored, display: true, animate: false)

            // Correction pass: ensure alignment after SwiftUI may enforce a larger min width.
            DispatchQueue.main.async {
                guard !isAdjustingWindowFrame else { return }
                isAdjustingWindowFrame = true
                defer { isAdjustingWindowFrame = false }

                guard let screenFrame2 = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

                let current = window.frame
                let targetX = screenFrame2.maxX - current.size.width - 20
                let targetY = screenFrame2.midY - current.size.height / 2

                // If we're already effectively aligned, don't force another layout pass.
                if abs(current.origin.x - targetX) < 1 && abs(current.origin.y - targetY) < 1 {
                    return
                }

                var corrected = current
                corrected.origin.x = targetX
                corrected.origin.y = targetY
                window.setFrame(corrected, display: true, animate: false)
            }
        }
    }

    private func showAccessibilityPreflightAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Allow Accessibility access"
            alert.informativeText = """
            Please grant me Accessibility access so I can type for you.
            """
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Quit")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Push our window behind others so the system Accessibility prompt
                // and System Settings are not obscured.
                if let window = NSApp.mainWindow ?? NSApp.windows.first {
                    window.orderBack(nil)
                }
                AccessibilityPermissionHelper.requestIfNeeded()
            default:
                NSApp.terminate(nil)
            }
        }
    }
}

#Preview {
    ContentView()
}

struct BlurOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Nothing to update dynamically for now.
    }
}

struct KoFiSupportButton: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Please support this app.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            // Ko-fi button
            Button {
                if let url = URL(string: "https://ko-fi.com/0xffr4bbit") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image("tip_ko-fi")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .padding(8)
                    .background(Color(hex: "#FF6433"))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("open Ko-fi")
            .hoverPointer()

            // Buy Me a Coffee button
            Button {
                if let url = URL(string: "https://buymeacoffee.com/0xff.r4bbit") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image("tip_buymeacoffee")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .padding(8)
                    .background(Color(hex: "#FFDD03"))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("open Buy Me a Coffee")
            .hoverPointer()
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }
}


private struct HoverPointerModifier: ViewModifier {
    @State private var isInside = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            // Prevent mismatched push/pop when views appear/disappear under an overlay.
            if inside {
                guard !isInside else { return }
                isInside = true
                NSCursor.pointingHand.push()
            } else {
                guard isInside else { return }
                isInside = false
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func hoverPointer() -> some View {
        self.modifier(HoverPointerModifier())
    }
}

private extension Color {
    init(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }

        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >> 8) / 255.0
            b = Double(value & 0x0000FF) / 255.0
        default:
            r = 0
            g = 0
            b = 0
        }

        self = Color(red: r, green: g, blue: b)
    }
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
