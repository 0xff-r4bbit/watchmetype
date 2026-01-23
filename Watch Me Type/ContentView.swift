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
    @State private var highlightEstimate: Bool = false
    @State private var useTotalTime: Bool = false
    @State private var hasShownAccessibilityAlert: Bool = false
    @State private var storedNormalWindowFrame: CGRect? = nil
    @State private var pendingWindowAdjustment: DispatchWorkItem? = nil
    private let defaultWindowWidth: CGFloat = 1000
    private let defaultWindowHeight: CGFloat = 675
    private let windowAdjustmentDebounce: TimeInterval = 0.05

    // Optional total duration
    @State private var desiredDurationValue: String = ""
    @State private var durationUnit: DurationUnit = .minutes

    // Two-draft editing mode
    @State private var inputTextDraft2: String = ""
    @State private var customEditingDuration: Bool = false
    @State private var editingDurationValue: String = ""
    @State private var editingDurationUnit: DurationUnit = .minutes

    @Environment(\.colorScheme) private var colorScheme

    // Error state for editing failures
    @State private var showEditingError: Bool = false
    @State private var editingErrorMessage: String = ""
    @State private var shareLinkCopied: Bool = false
    @State private var showWeChatPayOverlay: Bool = false

    @StateObject private var typingManager = TypingManager()

    private var isOverlayVisible: Bool {
        typingManager.state != .idle || typingManager.lastCompletionDate != nil
    }

    private var hasSecondDraft: Bool {
        !inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var estimatedEditingTime: TimeInterval? {
        guard hasSecondDraft,
              !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return typingManager.estimateEditingTime(
            draft1: inputText,
            draft2: inputTextDraft2,
            wpm: Int(targetWPM)
        )
    }

    var body: some View {
        ZStack {
            mainFormContent

            if isOverlayVisible {
                overlayContent
            }

            if showWeChatPayOverlay {
                // Semi-transparent background - tap to dismiss
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showWeChatPayOverlay = false
                    }

                // Centered QR code image
                Image("tip_qr_wechat-pay")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(radius: 20)
            }
        }
        .onAppear {
            handleAccessibilityOnAppear()
        }
        .onChange(of: targetWPM) { _, _ in
            flashEstimate()
        }
        .onChange(of: isOverlayVisible) { _, newValue in
            // When the overlay disappears entirely, ensure window level returns to normal.
            // Note: Window frame restoration is handled by the "Let's go again" button.
            if !newValue {
                DispatchQueue.main.async {
                    setWindowAlwaysOnTop(false)
                }
            }
        }
        .onChange(of: typingManager.state) { oldState, newState in
            DispatchQueue.main.async {
                let isRunActive = newState != .idle
                setWindowAlwaysOnTop(isRunActive)

                // Only resize when transitioning from idle to active (starting)
                if oldState == .idle && isRunActive {
                    compactWindowForOverlay()
                } else if newState == .idle && typingManager.lastCompletionDate != nil {
                    // Typing/editing finished - show compact completion overlay
                    compactWindowForCompletion()
                }
            }
        }
        .onChange(of: typingManager.lastEditingError) { _, error in
            if let error = error {
                editingErrorMessage = """
                \(error.localizedDescription)

                \(error.recoverySuggestion ?? "")

                This usually happens when:
                • You switched to a different window during editing
                • The document was modified externally
                • The target application didn't respond to keyboard input

                Please try again, and avoid interacting with other windows during editing.
                """
                showEditingError = true
                // Clear the error after handling
                typingManager.lastEditingError = nil
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

    @ViewBuilder
    private func tipIcon(
        imageName: String,
        size: CGFloat = 200,
        cornerRadius: CGFloat = 24
    ) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Extracted Views for Type-Checker Performance

    @ViewBuilder
    private var mainFormContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App header + support button
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch Me Type")
                        .font(.title)
                        .bold()

                    Text(.init("an [open-source](https://github.com/0xff-r4bbit/watchmetype) macOS app that mimics human typing and editing"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Spacer()

                KoFiSupportButton(showWeChatPayOverlay: $showWeChatPayOverlay)
            }

            HStack(alignment: .top, spacing: 16) {
                draftEditorsSection
                settingsColumn
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding()
        .frame(
            minWidth: isOverlayVisible ? defaultWindowWidth * 0.5 : defaultWindowWidth,
            minHeight: isOverlayVisible ? defaultWindowHeight * 0.5 : defaultWindowHeight
        )
        .allowsHitTesting(!isOverlayVisible)
    }

    @ViewBuilder
    private var draftEditorsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            draftEditorView(
                title: "Draft 1",
                text: $inputText,
                placeholder: "Paste what you want me to type here."
            )

            draftEditorView(
                title: "Draft 2 (optional)",
                text: $inputTextDraft2,
                placeholder: "Paste your final copy here if you have one."
            )
        }
    }

    @ViewBuilder
    private func draftEditorView(
        title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: text)
                    .padding(8)
                    .scrollIndicators(.hidden)

                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                        .padding(.top, 14)
                        .padding(.leading, 12)
                        .allowsHitTesting(false)
                }
            }
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

    @ViewBuilder
    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            cleanUpCard
            typingSpeedCard

            if hasSecondDraft {
                editingPhaseCard
            }

            HStack {
                Spacer()
                Button("Start") {
                    if hasSecondDraft {
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
                .buttonStyle(.borderedProminent)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .frame(width: 320, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var cleanUpCard: some View {
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
            .disabled(
                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var typingSpeedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("􀐳 Typing Speed")
                .font(.headline)
                .bold()

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

            VStack(alignment: .leading, spacing: 6) {
                if useTotalTime {
                    customDurationPicker
                } else {
                    estimatedTimeText
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var customDurationPicker: some View {
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
    }

    @ViewBuilder
    private var editingPhaseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("􁚝 Editing Phase")
                .font(.headline)
                .bold()

            Text("The app will type draft 1, then edit it to match draft 2.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Custom Editing Duration", isOn: $customEditingDuration)
                .font(.subheadline)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                if customEditingDuration {
                    editingDurationPicker
                } else {
                    estimatedEditingText
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var editingDurationPicker: some View {
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

    @ViewBuilder
    private var overlayContent: some View {
        let isCompletionOverlay = typingManager.state == .idle && typingManager.lastCompletionDate != nil
        let overlayBackground = isCompletionOverlay ? Color.white : Color.black.opacity(0.7)
        let overlayPrimaryText = isCompletionOverlay ? Color.black : Color.white
        let overlaySecondaryText = overlayPrimaryText.opacity(0.75)
        let overlayTertiaryText = overlayPrimaryText.opacity(0.8)

        BlurOverlay()
            .ignoresSafeArea()
            .overlay(
                overlayBackground
                    .ignoresSafeArea()
            )
            .contentShape(Rectangle())
            .onTapGesture { }

        VStack(spacing: 12) {
            if typingManager.state == .idle, typingManager.lastCompletionDate != nil {
                completionOverlayContent(
                    primaryText: overlayPrimaryText,
                    secondaryText: overlaySecondaryText,
                    tertiaryText: overlayTertiaryText
                )
            } else {
                activeOverlayContent(
                    primaryText: overlayPrimaryText,
                    secondaryText: overlaySecondaryText
                )
            }
        }
        .padding()
        .environment(\.colorScheme, isCompletionOverlay ? .light : colorScheme)
    }

    @ViewBuilder
    private func completionOverlayContent(
        primaryText: Color,
        secondaryText: Color,
        tertiaryText: Color
    ) -> some View {
        VStack(spacing: 12) {
            Text("Done")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(primaryText)

            if let subtitle = completionSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
                .frame(height: 16)

            Text("If this helped you, please consider donating and sharing this app.")
                .font(.subheadline)
                .foregroundColor(tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 32) {
                Button {
                    if let url = URL(string: "https://Ko-fi.com/0xffr4bbit") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    tipIcon(
                        imageName: "tip_qr_ko-fi",
                        size: 200,
                        cornerRadius: 24
                    )
                }
                .buttonStyle(.plain)
                .hoverPointer()

                tipIcon(
                    imageName: "tip_qr_wechat-pay",
                    size: 200,
                    cornerRadius: 24
                )
            }
            .padding(.vertical, 24)
        }
        .padding(.top, 10)

        HStack(spacing: 12) {
            Button(shareLinkCopied ? "Link copied!" : "Share this app.") {
                copyShareLink()
                shareLinkCopied = false
                typingManager.stopTyping()
                restoreNormalWindowFrame()
            }
            .buttonStyle(.bordered)

            Button("Let's go again.") {
                shareLinkCopied = false
                typingManager.stopTyping()
                restoreNormalWindowFrame()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func activeOverlayContent(
        primaryText: Color,
        secondaryText: Color
    ) -> some View {
        if typingManager.state == .countingDown {
            countdownOverlayContent(primaryText: primaryText, secondaryText: secondaryText)
        } else {
            typingOverlayContent(primaryText: primaryText, secondaryText: secondaryText)
        }

        Button(typingManager.state == .countingDown ? "Cancel" : "Stop") {
            typingManager.stopTyping()
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, typingManager.state == .countingDown ? 18 : 0)
    }

    @ViewBuilder
    private func countdownOverlayContent(
        primaryText: Color,
        secondaryText: Color
    ) -> some View {
        VStack(spacing: 10) {
            Text("Switch to where you want me to type.")
                .font(.title2)
                .bold()
                .foregroundColor(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 10)

            let remaining = max(0, typingManager.countdownRemaining)

            VStack(spacing: 6) {
                Text("Starting in")
                    .font(.subheadline)
                    .foregroundColor(secondaryText)

                Text("\(remaining)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(primaryText)
            }
            .accessibilityLabel("Starting in \(remaining) seconds")

            Spacer()
                .frame(height: 16)

            ProgressView()
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
                .opacity(0.7)
                .padding(.horizontal)

            Text(" ")
                .font(.caption)
                .opacity(0)
        }
    }

    @ViewBuilder
    private func typingOverlayContent(
        primaryText: Color,
        secondaryText: Color
    ) -> some View {
        let showProgressSection = typingManager.state == .typing
            || typingManager.state == .paused

        VStack(spacing: 10) {
            if let instruction = overlayPrimaryInstruction {
                Text(instruction)
                    .font(.title2)
                    .bold()
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }

            if let label = overlayPhaseLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
            }

            Text(statusText)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundColor(primaryText)

            Spacer()
                .frame(height: 16)

            ProgressView(value: typingManager.progressFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)
                .opacity(showProgressSection ? 0.7 : 0)
                .padding(.horizontal)
                .accessibilityHidden(!showProgressSection)
                .allowsHitTesting(showProgressSection)

            Text("\(Int(typingManager.progressFraction * 100))% complete")
                .font(.caption)
                .foregroundColor(secondaryText)
                .opacity(showProgressSection ? 1 : 0)
                .accessibilityHidden(!showProgressSection)
        }
    }

    private func copyShareLink() {
        let urlString = "https://github.com/0xff-r4bbit/watchmetype"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            shareLinkCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                shareLinkCopied = false
            }
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
            return "Starting…"
        case .typing:
            return typingManager.isThinking
                ? "Thinking"
                : "Typing"
        case .editing:
            return "Editing"
        case .paused:
            return "Paused"
        }
    }

    private var overlaySupportingText: String? {
        return nil
    }

    private var overlayPrimaryInstruction: String? {
        switch typingManager.state {
        case .typing, .editing:
            return "Stay in your document."
        case .paused:
            return "Switch back to your document to resume."
        case .idle:
            return nil
        case .countingDown:
            return nil
        }
    }

    private var overlayPhaseLabel: String? {
        switch typingManager.state {
        case .typing, .paused:
            return hasSecondDraft ? "Typing Phase (1 of 2)" : "Typing Phase"
        case .editing:
            return hasSecondDraft ? "Editing Phase (2 of 2)" : "Editing Phase"
        case .idle:
            return nil
        case .countingDown:
            return nil
        }
    }

    private var estimatedTimeText: Text {
        guard let minutes = estimatedMinutes else {
            return Text("Estimated: at least —")
                .foregroundColor(.secondary)
        }

        let prefix = Text("Estimated: at least ")
            .foregroundColor(.secondary)

        let number = Text("\(minutes)m")
            .bold()
            .foregroundColor(highlightEstimate ? .accentColor : .primary)

        return prefix + number
    }

    private var estimatedEditingText: Text {
        guard let editTime = estimatedEditingTime else {
            return Text("Estimated: at least —")
                .foregroundColor(.secondary)
        }

        let estimate = formatDurationInFiveMinuteIncrements(editTime)

        let prefix = Text("Estimated: at least ")
            .foregroundColor(.secondary)

        let value = Text(estimate)
            .bold()
            .foregroundColor(highlightEstimate ? .accentColor : .primary)

        return prefix + value
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

        // Check if we have separate phase durations (two-phase mode)
        if let typingDuration = typingManager.lastTypingPhaseDuration,
           let editingDuration = typingManager.lastEditingPhaseDuration {
            let typingStr = formatDuration(typingDuration)
            let editingStr = formatDuration(editingDuration)
            let totalStr = formatDuration(typingDuration + editingDuration)
            return "Finished at \(timeString)\nTyping \(typingStr)\nEditing \(editingStr)\nTotal \(totalStr)"
        } else if let duration = typingManager.lastRunDuration {
            let durationStr = formatDuration(duration)
            return "Finished at \(timeString)\nTotal \(durationStr)"
        } else {
            return "Finished at \(timeString)"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Formats duration as minutes rounded to nearest 5-minute increment
    /// Examples: "5m", "10m", "1h 15m"
    private func formatDurationInFiveMinuteIncrements(_ duration: TimeInterval) -> String {
        let totalMinutes = duration / 60.0

        // Round to nearest 5 minutes, minimum 5 minutes
        let roundedMinutes = max(5, Int((totalMinutes / 5.0).rounded()) * 5)

        if roundedMinutes >= 60 {
            let hours = roundedMinutes / 60
            let mins = roundedMinutes % 60
            if mins == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(mins)m"
            }
        } else {
            return "\(roundedMinutes)m"
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
        // Process both drafts
        inputText = processText(inputText)
        if !inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputTextDraft2 = processText(inputTextDraft2)
        }
    }

    private func processText(_ text: String) -> String {
        var result = text

        if removeBlankLines || removeHorizontalRules || removeBulletPoints {
            let lines = result.components(separatedBy: .newlines)
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

            result = newLines.joined(separator: "\n")
        }

        if removeEmojis {
            result = String(result.filter { !$0.isEmojiCharacter })
        }

        if replaceEmDashesWithCommas {
            result = replacingEmDashesWithCommas(in: result)
        }

        // Collapse multiple spaces into single spaces.
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // Remove stray spaces immediately before common punctuation.
        let punctuations = [",", ".", "!", "?", ":", ";"]
        for p in punctuations {
            let bad = " " + p
            while result.contains(bad) {
                result = result.replacingOccurrences(of: bad, with: p)
            }
        }

        return result
    }

    private func handleAccessibilityOnAppear() {
        // Only run this once per launch so we don't nag if the view reloads.
        guard !hasShownAccessibilityAlert else { return }
        hasShownAccessibilityAlert = true

        // Move the window out of the way as soon as it actually exists on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Set window to default size on first launch
            setWindowToDefaultSize()

            // Store the normal frame once (used to restore after the overlay compacts the window).
            storeNormalWindowFrameIfNeeded()

            moveWindowToRightEdge()

            // If we're not yet trusted, show our explanation alert.
            if !AccessibilityPermissionHelper.isTrusted {
                showAccessibilityPreflightAlert()
            }
        }
    }

    private func setWindowToDefaultSize() {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        var newFrame = window.frame
        newFrame.size.width = defaultWindowWidth
        newFrame.size.height = defaultWindowHeight

        // Keep window within screen bounds
        newFrame.origin.x = min(newFrame.origin.x, screenFrame.maxX - newFrame.size.width - 20)
        newFrame.origin.y = screenFrame.midY - newFrame.size.height / 2

        window.setFrame(newFrame, display: true, animate: false)
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
        // Status overlay (typing/editing/thinking): ~28% width, 50% height
        resizeWindowCompact(widthFraction: 0.2, heightFraction: 0.5)
    }

    private func compactWindowForCompletion() {
        // Completion overlay
        resizeWindowCompact(widthFraction: 0.66, heightFraction: 1)
        setWindowResizable(false)
    }

    private func setWindowResizable(_ resizable: Bool) {
        guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
        if resizable {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
        }
    }

    private func resizeWindowCompact(widthFraction: CGFloat, heightFraction: CGFloat) {
        // Cancel any pending window adjustment to prevent race conditions
        pendingWindowAdjustment?.cancel()

        let overlayWidth = defaultWindowWidth * widthFraction
        let overlayHeight = defaultWindowHeight * heightFraction
        let workItem = DispatchWorkItem {
            guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
            guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

            var newFrame = window.frame
            newFrame.size.width = overlayWidth
            newFrame.size.height = overlayHeight

            // Keep the right edge aligned to the screen's right edge (with a small margin).
            newFrame.origin.x = screenFrame.maxX - newFrame.size.width - 20

            // Keep the window vertically centred.
            newFrame.origin.y = screenFrame.midY - newFrame.size.height / 2

            window.setFrame(newFrame, display: true, animate: false)

            // Single delayed correction pass (instead of nested async)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
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

        pendingWindowAdjustment = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + windowAdjustmentDebounce, execute: workItem)
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

        // Re-enable window resizing (disabled during completion overlay)
        setWindowResizable(true)

        // Cancel any pending window adjustment to prevent race conditions
        pendingWindowAdjustment?.cancel()

        let workItem = DispatchWorkItem {
            guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }

            var restored = normal

            // Re-align to the right edge of the *current* display in case the window moved screens.
            if let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                restored.origin.x = screenFrame.maxX - restored.size.width - 20
                restored.origin.y = screenFrame.midY - restored.size.height / 2
            }

            window.setFrame(restored, display: true, animate: false)

            // Single delayed correction pass (instead of nested async)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
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

        pendingWindowAdjustment = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + windowAdjustmentDebounce, execute: workItem)
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
    @Binding var showWeChatPayOverlay: Bool

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

            // WeChat Pay button
            Button {
                showWeChatPayOverlay = true
            } label: {
                Image("tip_wechat-pay")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .padding(8)
                    .background(Color(hex: "#07C160"))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("WeChat Pay")
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
