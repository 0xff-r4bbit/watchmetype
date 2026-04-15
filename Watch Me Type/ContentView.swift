import SwiftUI
import AppKit

// MARK: - Native Text Editor with Proper Scroll Behavior

/// NSScrollView subclass that prevents intrinsic content size from inflating SwiftUI layout.
private class FixedIntrinsicScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var accessibilityLabel: String = "Text editor"
    var isFocused: Binding<Bool>? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = FixedIntrinsicScrollView()
        let textView = NSTextView()

        // Configure text view
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(accessibilityLabel)

        // Configure scroll view - key settings for proper scroll indicator behavior
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true  // This is the key setting
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>?

        init(text: Binding<String>, isFocused: Binding<Bool>?) {
            self.text = text
            self.isFocused = isFocused
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
        }
    }
}

private struct DraftEditor: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let editorAccessibilityLabel: String
    @State private var isFocused: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                NativeTextEditor(
                    text: $text,
                    accessibilityLabel: editorAccessibilityLabel,
                    isFocused: $isFocused
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(8)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundColor(.secondary)
                        .padding(.top, 9)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isFocused ? Color.accentColor : Color.secondary.opacity(0.3),
                            lineWidth: isFocused ? 2 : 1)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)

            let wordCount = text
                .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace || $0.isNewline })
                .count
            Text("\(wordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

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
    @State private var removeListNumbering: Bool = false
    @State private var replaceEmDashesWithCommas: Bool = false
    @State private var highlightEstimate: Bool = false
    @State private var useTotalTime: Bool = false
    @State private var hasShownAccessibilityAlert: Bool = false
    @State private var storedNormalWindowFrame: CGRect? = nil
    @State private var pendingWindowAdjustment: DispatchWorkItem? = nil
    private let defaultWindowWidth: CGFloat = 1000
    private let defaultWindowHeight: CGFloat = 840
    private let windowAdjustmentDebounce: TimeInterval = 0.05

    // Optional total duration
    @State private var desiredDurationValue: String = ""
    @State private var durationUnit: DurationUnit = .minutes

    // Two-draft editing mode
    @State private var showDraft2: Bool = false
    @State private var inputTextDraft2: String = ""
    @State private var showDraft3: Bool = false
    @State private var inputTextDraft3: String = ""
    @State private var customEditingDuration: Bool = false
    @State private var editingDurationValue: String = ""
    @State private var editingDurationUnit: DurationUnit = .minutes

    @Environment(\.colorScheme) private var colorScheme

    // Scaled display font sizes — grow with the user's Dynamic Type setting
    @ScaledMetric(relativeTo: .largeTitle) private var doneFontSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var statusFontSize: CGFloat = 64

    @State private var showStartConfirmation: Bool = false

    // Error state for editing failures
    @State private var showEditingError: Bool = false
    @State private var editingErrorMessage: String = ""
    @State private var shareLinkCopied: Bool = false
    @State private var showWeChatPayOverlay: Bool = false
    @State private var showHumanizeSheet: Bool = false
    @State private var showHowItWorksSheet: Bool = false




    @StateObject private var typingManager = TypingManager()

    private var isOverlayVisible: Bool {
        typingManager.state != .idle || typingManager.lastCompletionDate != nil
    }

    private var hasFirstDraft: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSecondDraft: Bool {
        !inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasThirdDraftText: Bool {
        !inputTextDraft3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    .accessibilityLabel("WeChat Pay QR code for donations. Tap outside to dismiss.")
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

                if oldState == .idle && isRunActive {
                    compactWindowForOverlay()
                } else if newState == .idle && typingManager.lastCompletionDate != nil {
                    // Typing/editing finished - show compact completion overlay
                    compactWindowForCompletion()
                } else if newState == .idle && oldState != .idle && typingManager.lastCompletionDate == nil {
                    // Cancelled (e.g. countdown cancel) — restore window, right edge flush with display
                    restoreWindowToRightEdge()
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
        .alert("Ready to type?", isPresented: $showStartConfirmation) {
            Button("Start") {
                if hasSecondDraft {
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
                    typingManager.startTyping(
                        text: inputText,
                        wpm: Int(targetWPM),
                        countdown: 10,
                        totalDurationSeconds: desiredDurationSeconds,
                        simulateMistakes: true
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll have 10 seconds to switch to your target window.\n\n⚠️ Make sure auto-correct is turned off in the destination document before continuing.")
        }
        .alert("Editing Error", isPresented: $showEditingError) {
            Button("OK", role: .cancel) {
                typingManager.stopTyping()
            }
        } message: {
            Text(editingErrorMessage)
        }
        .sheet(isPresented: $showHumanizeSheet) {
            HumanizeSheetView()
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
            // App header + donation buttons
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Text("Watch Me Type")
                        .font(.title)
                        .bold()

                    Button {
                        showHowItWorksSheet = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .iconButtonHighlight()
                    .accessibilityHint("Opens instructions for using the app")
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Support this project")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    KoFiSupportButton(showWeChatPayOverlay: $showWeChatPayOverlay)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                draftEditorsSection
                    .frame(maxHeight: .infinity)
                settingsColumn
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .frame(
            minWidth: isOverlayVisible ? defaultWindowWidth * 0.5 : defaultWindowWidth,
            idealWidth: defaultWindowWidth
        )
        .allowsHitTesting(!isOverlayVisible)
    }

    private var bothDraftsEmpty: Bool {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && inputTextDraft2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var draftEditorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    draftEditorView(
                        title: "Draft 1",
                        text: $inputText,
                        placeholder: "Paste your initial draft here.",
                        editorAccessibilityLabel: "Draft 1 text editor"
                    )

                    Toggle("I have a draft 2", isOn: $showDraft2)
                        .font(.subheadline)
                }

                if showDraft2 {
                    draftEditorView(
                        title: "Draft 2",
                        text: $inputTextDraft2,
                        placeholder: "Paste your final draft here.",
                        editorAccessibilityLabel: "Draft 2 text editor"
                    )
                }
            }
        }
        .sheet(isPresented: $showHowItWorksSheet) {
            howItWorksSheet
        }
    }

    @ViewBuilder
    private var howItWorksSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("How it works")
                    .font(.headline)
                Spacer()
                Button { showHowItWorksSheet = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .iconButtonHighlight()
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(.init("Watch Me Type is an [open-source](https://github.com/0xff-r4bbit/watchmetype) macOS app. It types for you, the way a person actually types."))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                instructionRow(number: "1", text: "Drop your text into Draft 1.")

                instructionRow(number: "2", text: "Want the writing to sound less like a chatbot? Hit Humanize. You'll get a set of style rules to paste alongside your draft in whatever AI tool you use.")

                instructionRow(number: "3", text: "Got a revised version? Paste it into Draft 2. The app will type your first draft, then edit its way toward the second, pauses and all.")

                instructionRow(number: "4", text: "Press Start. You have ten seconds to switch over to the app you actually want to type into.")

                instructionRow(number: "5", text: "Now sit back. Watch Me Type handles the rest, one keystroke at a time.")
            }
            .padding()

            Spacer()
        }
        .frame(width: 520, height: 460)
    }

    @ViewBuilder
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.title)
                .bold()
                .foregroundColor(.accentColor)
                .frame(width: 28)
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
        }
    }

    @ViewBuilder
    private func draftEditorView(
        title: String,
        text: Binding<String>,
        placeholder: String,
        editorAccessibilityLabel: String = "Text editor"
    ) -> some View {
        DraftEditor(
            title: title,
            text: text,
            placeholder: placeholder,
            editorAccessibilityLabel: editorAccessibilityLabel
        )
    }

    @ViewBuilder
    private var humanizeButton: some View {
        Button { showHumanizeSheet = true } label: {
            Label("Humanize", systemImage: "wand.and.sparkles")
                .font(.body)
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(
            HumanizeButtonStyle(isEnabled: hasFirstDraft)
        )
        .disabled(!hasFirstDraft)
        .accessibilityHint("Opens writing-style rules to make AI text sound more natural")
    }

    @ViewBuilder
    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Align with draft editor boxes (below "Draft 1" label + spacing)
            Spacer()
                .frame(height: 16)

            humanizeButton
                // Extra horizontal space so glow shadow isn't clipped by parent
                .padding(.horizontal, 4)

            cleanUpCard
            typingSpeedCard
            if showDraft2 {
                editingCard
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                if !hasFirstDraft {
                    Text("Paste text in Draft 1 to start")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    showStartConfirmation = true
                } label: {
                    Text("Start")
                        .font(.title3)
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(StartButtonStyle(isEnabled: hasFirstDraft))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!hasFirstDraft)
                .accessibilityHint(!hasFirstDraft
                    ? "Paste text in Draft 1 to enable"
                    : "Starts typing simulation with a 10-second countdown")
            }
        }
        .frame(width: 320, alignment: .topLeading)
    }

    @ViewBuilder
    private var cleanUpCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Clean-Up", systemImage: "wand.and.rays")
                .font(.headline)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Remove blank lines", isOn: $removeBlankLines)
                    .help("Removes empty lines between paragraphs")
                Toggle("Remove emojis", isOn: $removeEmojis)
                    .help("Strips all emoji characters from the text")
                Toggle("Remove horizontal rules", isOn: $removeHorizontalRules)
                    .help("Removes lines made of dashes, underscores, or asterisks (---)")
                Toggle("Remove bullet points (- ...)", isOn: $removeBulletPoints)
                    .help("Removes dash or bullet markers at the start of lines")
                Toggle("Remove list numbering (1. , a. , i. ...)", isOn: $removeListNumbering)
                    .help("Removes numbered, lettered, and roman numeral list prefixes")
                Toggle("Replace em-dashes with commas", isOn: $replaceEmDashesWithCommas)
                    .help("Replaces em-dashes with a comma and space")

                Button("Apply to All Drafts") {
                    processInputText()
                }
                .buttonStyle(HoverHighlightButtonStyle(isEnabled: !bothDraftsEmpty))
                .disabled(bothDraftsEmpty)
                .accessibilityHint(bothDraftsEmpty
                    ? "Paste text into a draft to enable clean-up"
                    : "Applies selected clean-up rules to all drafts")
                .padding(.top, 4)
            }
            .padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var typingSpeedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Typing Speed", systemImage: "keyboard")
                .font(.headline)
                .bold()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target Speed: \(Int(targetWPM)) WPM")
                        .font(.subheadline)

                    Slider(value: $targetWPM, in: 40...120, step: 10)

                    HStack {
                        Image(systemName: "tortoise")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("Slow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("avg. human")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Fast")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Image(systemName: "hare")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("40")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("120")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Custom Typing Duration", isOn: $useTotalTime)
                    .font(.subheadline)
                    .help("Override the estimated typing time with a specific duration")

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
            .padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    private var editingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Editing", systemImage: "pencil.and.outline")
                .font(.headline)
                .bold()

            VStack(alignment: .leading, spacing: 12) {
                Text(hasSecondDraft
                    ? "The app will type draft 1, then edit it to match draft 2."
                    : "Paste text in Draft 2 to enable the editing phase.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Custom Editing Duration", isOn: $customEditingDuration)
                    .font(.subheadline)

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
            .padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .opacity(hasSecondDraft ? 1.0 : 0.5)
        .disabled(!hasSecondDraft)
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
        let overlayBackground = Color.black.opacity(0.7)
        let overlayPrimaryText = Color.white
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
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func completionOverlayContent(
        primaryText: Color,
        secondaryText: Color,
        tertiaryText: Color
    ) -> some View {
        VStack(spacing: 16) {
            // 1. Heading
            Text("Done")
                .font(.system(size: doneFontSize, weight: .bold, design: .rounded))
                .foregroundColor(primaryText)
                .accessibilityAddTraits(.isHeader)

            // 2. Completion summary — primary content
            if let subtitle = completionSubtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundColor(secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
                .frame(height: 8)

            // 3. Appreciation + donation — secondary
            Text("If this helped you, please consider donating and sharing this app.")
                .font(.caption)
                .foregroundColor(tertiaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Button {
                        if let url = URL(string: "https://Ko-fi.com/0xffr4bbit") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        tipIcon(
                            imageName: "tip_qr_ko-fi",
                            size: 120,
                            cornerRadius: 16
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverPointer()
                    .accessibilityLabel("Donate via Ko-fi")

                    Text("Donate via Ko-fi")
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                }

                VStack(spacing: 4) {
                    Button {
                        showWeChatPayOverlay = true
                    } label: {
                        tipIcon(
                            imageName: "tip_qr_wechat-pay",
                            size: 120,
                            cornerRadius: 16
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverPointer()
                    .accessibilityLabel("Donate via WeChat Pay")

                    Text("Donate via WeChat Pay")
                        .font(.caption2)
                        .foregroundColor(secondaryText)
                }
            }
            .padding(.vertical, 8)
        }
        .padding(.top, 10)

        HStack(spacing: 12) {
            Button(shareLinkCopied ? "Link copied!" : "Copy share link") {
                copyShareLink()
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Copies the app's GitHub link to the clipboard")

            Button("Let's go again") {
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

        HStack(spacing: 12) {
            if typingManager.state == .countingDown {
                Button("Cancel") {
                    typingManager.stopTyping()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
            } else if typingManager.state == .typing {
                Button("Pause") {
                    typingManager.pauseTypingFromUI()
                }
                .buttonStyle(.bordered)

                Button("Stop") {
                    typingManager.stopTyping()
                }
                .buttonStyle(.borderedProminent)
            } else if typingManager.state == .paused {
                Button("Resume") {
                    typingManager.resumeTypingFromUI()
                }
                .buttonStyle(.borderedProminent)

                Button("Stop") {
                    typingManager.stopTyping()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Stop") {
                    typingManager.stopTyping()
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
                    .font(.system(size: doneFontSize, weight: .bold, design: .rounded))
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
                HStack(spacing: 8) {
                    if typingManager.state == .typing || typingManager.state == .editing {
                        Image(systemName: "doc.text")
                            .font(.title2)
                            .foregroundColor(primaryText)
                    }
                    Text(instruction)
                        .font(.title2)
                        .bold()
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
                .padding(.bottom, 10)
            }

            if let label = overlayPhaseLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(secondaryText)
            }

            Text(statusText)
                .font(.system(size: statusFontSize, weight: .bold, design: .rounded))
                .foregroundColor(primaryText)
                .accessibilityLabel("Status: \(statusText)")

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
        let hasThirdDraft = showDraft2 && showDraft3 && hasThirdDraftText
        switch typingManager.state {
        case .typing, .paused:
            if hasThirdDraft {
                return "Typing Phase (1 of 3)"
            } else if hasSecondDraft {
                return "Typing Phase (1 of 2)"
            } else {
                return "Typing Phase"
            }
        case .editing:
            if hasThirdDraft {
                return typingManager.progressFraction < 0.66
                    ? "Editing Phase (2 of 3)"
                    : "Editing Phase (3 of 3)"
            } else if hasSecondDraft {
                return "Editing Phase (2 of 2)"
            } else {
                return "Editing Phase"
            }
        case .idle, .countingDown:
            return nil
        }
    }

    private var estimatedTimeText: Text {
        guard let minutes = estimatedMinutes else {
            return Text("")
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
            return Text("")
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

        if let typingDuration = typingManager.lastTypingPhaseDuration,
           let edit1Duration = typingManager.lastEditingPhaseDuration,
           let edit2Duration = typingManager.lastEditingPhase2Duration {
            let typingStr = formatDuration(typingDuration)
            let edit1Str = formatDuration(edit1Duration)
            let edit2Str = formatDuration(edit2Duration)
            let totalStr = formatDuration(typingDuration + edit1Duration + edit2Duration)
            return "Finished at \(timeString)\nTyping \(typingStr)\nEditing 1 \(edit1Str)\nEditing 2 \(edit2Str)\nTotal \(totalStr)"
        } else if let typingDuration = typingManager.lastTypingPhaseDuration,
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

        // List numbering is stripped after the per-line pass so the full set of
        // lines is available for cross-line sequence detection (see processListNumbering).
        if removeListNumbering {
            result = processListNumbering(in: result.components(separatedBy: .newlines))
                .joined(separator: "\n")
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

        // Strip any leading spaces from each line (e.g. left behind after list-prefix removal).
        result = result.components(separatedBy: .newlines)
            .map { String($0.drop(while: { $0 == " " })) }
            .joined(separator: "\n")

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

        // Lock the minimum size immediately so SwiftUI's layout can't shrink below it.
        if let window = NSApp.mainWindow ?? NSApp.windows.first {
            window.minSize = NSSize(width: defaultWindowWidth * 0.6, height: defaultWindowHeight)
        }

        // Wait for SwiftUI's initial layout pass to finish, then enforce our frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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

        // Lock minimum size to the fixed window height
        window.minSize = NSSize(width: defaultWindowWidth * 0.6, height: defaultWindowHeight)

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
        resizeWindowCompact(widthFraction: 0.2)
    }

    private func compactWindowForCompletion() {
        resizeWindowCompact(widthFraction: 0.66)
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

    private func resizeWindowCompact(widthFraction: CGFloat) {
        pendingWindowAdjustment?.cancel()

        let overlayWidth = defaultWindowWidth * widthFraction
        let workItem = DispatchWorkItem {
            guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
            guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

            var newFrame = window.frame
            newFrame.size.width = overlayWidth

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

    private func restoreWindowToRightEdge() {
        setWindowResizable(true)
        pendingWindowAdjustment?.cancel()

        let workItem = DispatchWorkItem {
            guard let window = NSApp.mainWindow ?? NSApp.windows.first else { return }
            guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

            var restored = self.storedNormalWindowFrame ?? window.frame

            // Right edge flush with display right edge
            restored.origin.x = screenFrame.maxX - restored.size.width
            restored.origin.y = screenFrame.midY - restored.size.height / 2

            window.setFrame(restored, display: true, animate: true)
        }

        pendingWindowAdjustment = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + windowAdjustmentDebounce, execute: workItem)
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
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Open Ko-fi")
            .accessibilityLabel("Donate via Ko-fi")
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
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Donate via WeChat Pay")
            .accessibilityLabel("Donate via WeChat Pay")
            .hoverPointer()
        }
    }
}

private struct HumanizeSheetView: View {
    enum LoadState {
        case loading
        case loaded(String)
        case error(String)
    }

    @State private var loadState: LoadState = .loading
    @State private var copied: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Label("Humanize Your Writing", systemImage: "wand.and.sparkles")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .iconButtonHighlight()
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Content
            switch loadState {
            case .loading:
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Pulling latest humanizing techniques...")
                        .foregroundStyle(.secondary)
                }
                Spacer()

            case .loaded(let guide):
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is this?")
                            .font(.subheadline)
                            .bold()
                        Text("These are writing-style rules that make AI-generated text sound more natural. Copy them into ChatGPT, Claude, or another AI assistant along with your draft to get a more human-sounding revision.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    Text("Copy the rules below and feed them into your AI of choice along with your final draft.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    // Code block with copy button
                    ZStack(alignment: .topTrailing) {
                        ScrollView {
                            Text(guide)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )

                        // Copy button
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(guide, forType: .string)
                            copied = true
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                copied = false
                            }
                        } label: {
                            Label(
                                copied ? "Copied!" : "Copy",
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .iconButtonHighlight()
                        .padding(8)
                    }
                    .padding(.horizontal)

                    // Refresh button
                    HStack {
                        Spacer()
                        Button {
                            loadState = .loading
                            HumanizerService.clearCache()
                            Task { await fetchGuide() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

            case .error:
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Something went wrong")
                        .font(.headline)
                    Text("We couldn't generate humanization rules right now. Please try again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Try Again") {
                        loadState = .loading
                        HumanizerService.clearCache()
                        Task { await fetchGuide() }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .frame(width: 600, height: 500)
        .task { await fetchGuide() }
    }

    private func fetchGuide() async {
        do {
            let guide = try await HumanizerService.fetchGuide()
            loadState = .loaded(guide)
        } catch {
            appLog("Failed to fetch humanizer guide: \(error)", level: .error)
            loadState = .error(error.localizedDescription)
        }
    }
}

/// Prominent Start button with hover glow, press inset, and a subtle focus ring.
/// Mirrors HumanizeButtonStyle visually, but in the system accent/blue palette
/// and without the rotating border.
private struct HoverHighlightButtonStyle: ButtonStyle {
    let isEnabled: Bool
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(background(isPressed: isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.15),
                            lineWidth: isFocused ? 2 : 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .focusable(isEnabled)
            .focused($isFocused)
            .onHover { hovering in
                guard isEnabled else { return }
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }

    private func background(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.primary.opacity(0.05) }
        if isPressed { return Color.accentColor.opacity(0.25) }
        if isHovering { return Color.accentColor.opacity(0.15) }
        return Color.primary.opacity(0.06)
    }
}

private struct StartButtonStyle: ButtonStyle {
    let isEnabled: Bool

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .foregroundColor(isEnabled ? .white : .secondary)
            .background(backgroundFill(isPressed: isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(isPressed: isPressed), lineWidth: isHovering ? 2 : 1)
            )
            .shadow(
                color: hoverShadowColor(isPressed: isPressed),
                radius: hoverShadowRadius(isPressed: isPressed),
                x: 0,
                y: isPressed ? 0 : 1
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isPressed)
            .animation(.easeOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        if !isEnabled {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        } else if isPressed {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.75), Color.accentColor.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if isHovering {
            LinearGradient(
                colors: [Color.accentColor.opacity(1.0), Color.accentColor.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func borderColor(isPressed: Bool) -> Color {
        guard isEnabled else { return Color.secondary.opacity(0.08) }
        if isPressed { return Color.accentColor.opacity(0.5) }
        if isHovering { return Color.white.opacity(0.35) }
        return Color.white.opacity(0.15)
    }

    private func hoverShadowColor(isPressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if isPressed { return Color.accentColor.opacity(0.2) }
        if isHovering { return Color.accentColor.opacity(0.55) }
        return .clear
    }

    private func hoverShadowRadius(isPressed: Bool) -> CGFloat {
        guard isEnabled else { return 0 }
        if isPressed { return 3 }
        if isHovering { return 14 }
        return 0
    }
}

private struct HumanizeButtonStyle: ButtonStyle {
    let isEnabled: Bool

    // Gold palette
    private let goldBase = Color(red: 0.85, green: 0.65, blue: 0.13)
    private let goldDark = Color(red: 0.78, green: 0.55, blue: 0.08)
    private let goldBright = Color(red: 0.95, green: 0.80, blue: 0.25)

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        configuration.label
            .foregroundColor(isEnabled ? .white : .secondary)
            .background(backgroundFill(isPressed: isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(borderOverlay(isPressed: isPressed))
            .shadow(
                color: hoverShadowColor(isPressed: isPressed),
                radius: hoverShadowRadius(isPressed: isPressed),
                x: 0,
                y: isPressed ? 0 : 1
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isPressed)
            .animation(.easeOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    @ViewBuilder
    private func backgroundFill(isPressed: Bool) -> some View {
        if !isEnabled {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        } else if isPressed {
            LinearGradient(
                colors: [goldDark, goldDark.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
        } else if isHovering {
            LinearGradient(
                colors: [goldBright.opacity(0.9), goldBase],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            LinearGradient(
                colors: [goldBase, goldDark],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func borderOverlay(isPressed: Bool) -> some View {
        if !isEnabled {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
        } else if isPressed {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(goldDark.opacity(0.3), lineWidth: 1)
        } else if isHovering {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(goldBright.opacity(0.9), lineWidth: 2)
        } else {
            // Rotating angular gradient border in default state, time-driven so
            // it keeps spinning regardless of view re-renders.
            TimelineView(.animation) { context in
                let angle = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 3.0) / 3.0 * 360.0
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.white.opacity(0.9),
                                goldBright,
                                goldBase.opacity(0.3),
                                goldDark.opacity(0.2),
                                goldBase.opacity(0.3),
                                goldBright,
                                Color.white.opacity(0.9)
                            ],
                            center: .center,
                            angle: .degrees(angle)
                        ),
                        lineWidth: 2
                    )
            }
        }
    }

    /// Shadow only appears on hover and press — default state has no glow.
    private func hoverShadowColor(isPressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if isPressed { return goldDark.opacity(0.15) }
        if isHovering { return goldBase.opacity(0.55) }
        return .clear
    }

    private func hoverShadowRadius(isPressed: Bool) -> CGFloat {
        guard isEnabled else { return 0 }
        if isPressed { return 3 }
        if isHovering { return 14 }
        return 0
    }
}

/// Gives plain icon buttons a hover background, a focus ring, and a pointer cursor
/// so they communicate affordance for mouse and keyboard users alike.
private struct IconButtonHighlightModifier: ViewModifier {
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: isFocused ? 2 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: isHovering)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            .focusable(true)
            .focused($isFocused)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
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

    func iconButtonHighlight() -> some View {
        self.modifier(IconButtonHighlightModifier())
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

/// Strips list-numbering prefixes from a set of lines using cross-line sequence detection.
///
/// A prefix is only removed if it belongs to a run of ≥2 consecutive items in the same
/// numbering scheme (e.g. "I." alone is left untouched, but "I." + "II." + "III." are all
/// stripped). This eliminates false positives like "I. think…" or "A. Lincoln…".
///
/// Hierarchical patterns (1.2., A.1., etc.) are always stripped — false positives are
/// essentially impossible for multi-segment dot notation.
///
/// Recognised families:
///   Numeric:      1.  1)  1).  1:  (1)
///   Hierarchical: 1.2.  1.2.3.  1.a.  A.1.  A.1.a.
///   Roman:        i.  i)  i:  (i)  — lowercase & uppercase, up to xx (20)
///   Alpha:        a.  a)  a:  (a)  — lowercase & uppercase ASCII letters
private func processListNumbering(in lines: [String]) -> [String] {
    struct Hit {
        let lineIndex: Int
        let family: String   // groups lines belonging to the same numbering scheme
        let value: Int       // ordinal position within the scheme (1, 2, 3 …)
        let prefix: String   // exact characters to strip from the trimmed line
    }

    // Roman numeral table — longest strings first within each collision group so
    // that "i" never matches before "ii", "iii", etc.
    let romanTable: [(String, Int)] = [
        ("xviii", 18), ("xvii", 17), ("xvi", 16), ("xix", 19), ("xiv", 14),
        ("xiii", 13), ("xv", 15), ("xx", 20),
        ("viii", 8), ("xii", 12), ("vii", 7), ("xi", 11),
        ("iii", 3), ("ix", 9), ("vi", 6), ("iv", 4), ("ii", 2),
        ("i", 1), ("v", 5), ("x", 10), ("l", 50), ("c", 100), ("d", 500), ("m", 1000),
    ]

    // Numeric patterns with a capture group for the number value.
    let numericSpecs: [(pattern: String, family: String)] = [
        (#"^\((\d+)\)"#,  "numeric-wrapped"),
        (#"^(\d+)\)\."#,  "numeric-dotparen"),
        (#"^(\d+)\."#,    "numeric-dot"),
        (#"^(\d+)\)"#,    "numeric-paren"),
        (#"^(\d+):"#,     "numeric-colon"),
    ]

    var hits: [Hit] = []

    for (idx, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }

        // Records a hit only when the candidate prefix is followed by whitespace or EOL,
        // ensuring we don't match e.g. "ivy" when looking for "iv".
        let record: (String, String, Int) -> Void = { prefix, family, value in
            guard trimmed.hasPrefix(prefix) else { return }
            let tail = trimmed.dropFirst(prefix.count)
            guard tail.isEmpty || tail.first!.isWhitespace else { return }
            hits.append(Hit(lineIndex: idx, family: family, value: value, prefix: prefix))
        }

        // Numeric (only the first matching spec is recorded per line).
        for (pattern, family) in numericSpecs {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let match = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  match.numberOfRanges > 1,
                  let numRange = Range(match.range(at: 1), in: trimmed),
                  let value = Int(trimmed[numRange])
            else { continue }
            let matchRange = Range(match.range, in: trimmed)!
            let prefix = String(trimmed[..<matchRange.upperBound])
            let tail = trimmed[matchRange.upperBound...]
            if tail.isEmpty || tail.first!.isWhitespace {
                hits.append(Hit(lineIndex: idx, family: family, value: value, prefix: prefix))
                break
            }
        }

        // Roman numerals (both cases generate separate family hits).
        for (numeral, value) in romanTable {
            for (caseLabel, casedNumeral) in [("lower", numeral), ("upper", numeral.uppercased())] {
                record("(\(casedNumeral))", "roman-\(caseLabel)-wrapped", value)
                for delim in [".", ")", ":"] {
                    record(casedNumeral + delim, "roman-\(caseLabel)-\(delim)", value)
                }
            }
        }

        // Single ASCII letter — generates hits in the alpha family (separate from roman).
        // Ambiguous chars like "i" generate both roman AND alpha hits; the sequence check
        // resolves which family (if any) actually forms a run.
        if let firstChar = trimmed.first, firstChar.isLetter, firstChar.isASCII {
            let base: Character = firstChar.isUppercase ? "A" : "a"
            let alphaVal = Int(firstChar.asciiValue!) - Int(base.asciiValue!) + 1
            let caseLabel = firstChar.isUppercase ? "upper" : "lower"
            record("(\(firstChar))", "alpha-\(caseLabel)-wrapped", alphaVal)
            for delim in [".", ")", ":"] {
                record(String(firstChar) + delim, "alpha-\(caseLabel)-\(delim)", alphaVal)
            }
        }
    }

    // Group hits by family, then find consecutive runs of ≥2 values.
    var byFamily: [String: [Hit]] = [:]
    for hit in hits { byFamily[hit.family, default: []].append(hit) }

    var confirmed: [Int: String] = [:]   // lineIndex → prefix to strip
    for (_, group) in byFamily {
        let sorted = group.sorted { $0.value < $1.value }
        var j = 0
        while j < sorted.count {
            var k = j + 1
            while k < sorted.count && sorted[k].value == sorted[k - 1].value + 1 { k += 1 }
            if k - j >= 2 {
                for m in j..<k where confirmed[sorted[m].lineIndex] == nil {
                    confirmed[sorted[m].lineIndex] = sorted[m].prefix
                }
            }
            j = k
        }
    }

    // Hierarchical regex — always stripped, no sequence check needed.
    let hierarchicalRe = try? NSRegularExpression(pattern: #"^[A-Za-z\d]+(?:\.[A-Za-z\d]+)+\.?\s+"#)

    return lines.enumerated().map { (i, line) in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let indentCount = line.count - trimmed.count
        let indent = String(repeating: " ", count: indentCount)

        if let re = hierarchicalRe,
           let match = re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            return indent + String(trimmed[Range(match.range, in: trimmed)!.upperBound...])
        }

        guard let prefix = confirmed[i] else { return line }
        return indent + String(trimmed.dropFirst(prefix.count).drop(while: { $0 == " " }))
    }
}
