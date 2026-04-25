<table align="center">
  <tr>
    <td>
      <p align="center"><strong>⚠️ Warning ⚠️</strong></p>
      <p>Turn off autocorrect before typing with this app. Autocorrect can interfere with realistic drafting, especially when your draft includes intentional grammar or spelling mistakes. Here's how you can disable it in <a href="https://support.google.com/docs/answer/12022089?hl=en&co=GENIE.Platform%3DDesktop">Google Docs</a> and <a href="https://support.microsoft.com/en-us/office/turn-autocorrect-on-or-off-in-word-9f5a0684-05f6-4510-b419-8f0034caefe4">Microsoft Word</a>.</p>
    </td>
  </tr>
</table>

# Watch Me Type

_because revision history is not learning_

Watch Me Type is an open-source macOS app that types text into any active window with the pacing, pauses, and imperfections of a real person. It can replay a single draft, stage a Draft 1 → Draft 2 revision, or chain a Draft 2 → Draft 3 forward pass. While it runs, it locks to the chosen window, auto-pauses on focus changes, and keeps going for at least as long as you ask.

![Watch Me Type in action](assets/thumbnail.png)

## Purpose

> TL;DR: to force those in charge in education to give teachers the resources they need to adapt to the ubiquity of AI

In the face of genAI, education systems have responded by doubling down on surveillance. Teachers are asked to rely on tools like GPTZero, document revision history, and other forms of process forensics to prove whether a piece of writing is _real_. The burden of this work is pushed downward while the underlying problem is left untouched.

This approach misunderstands both writing and learning. Students do not write in clean, traceable steps. They think out of order. They draft on phones, in notes apps, on paper, in fragments. Or, maybe since teachers just check the final product, students get something like ChatGPT to generate that for them. It's not them being deceitful or devious; _students will always take the path of least resistance._

**Watch Me Type** exists inside this mess. Not to endorse it, but to expose it. If institutions insist on authentic-looking process instead of authentic _learning_, then the process itself becomes something students must manufacture.

The solution is not better detection; it's building actual relationships with students and evaluating the growth of their skills. That requires time, trust, and institutional support for teachers to design tasks that cannot be reduced to a final product check.

**To students:**

> A calculator makes it much easier to cheat on your math test, but it doesn't mean you don't need math in your life. _Apply yourself._

**To my fellow teachers:**

> Until institutions and governing bodies provide the necessary resources for you to adapt to this new age of AI, I am sorry for the chaos this may create in your classrooms.

**To those in charge in education:**

> You put teachers through school to learn about backwards design and competency-based assessments, but without time, staffing, and institutional support, teachers have to resort to policing student work just to make sure the students _might_ be learning. _Please_ give teachers the resources they need to actually do their job well and, maybe, you just might prevent their burnout.

## Features

- simulates human typing with adjustable 40–120 WPM, thinking pauses, comma/sentence/paragraph delays, and occasional mistakes with backspaces
- three modes: single-draft typing, two-phase draft1→draft2 editing (right-to-left edits to avoid cursor drift), or three-phase draft1→draft2→draft3 chaining that adds a left-to-right forward pass with offset-tracked navigation
- duration control: auto-estimated or custom minimum typing/editing time targets ("at least") with live progress tracking and a 10-second countdown
- text clean-up tools: remove blank lines/emojis/bullets/horizontal rules and numbered list prefixes, replace em-dashes, and normalise spacing before and within punctuation when processed
- safe edits: every destructive edit verifies expected text against an internal document snapshot and aborts on mismatch, so a focus glitch or stray keystroke can't silently corrupt the target document
- focus-aware: locks to the chosen app/window; typing auto-pauses and auto-resumes when focus returns; editing aborts on focus loss for safety; overlays for countdown/typing/thinking/editing/paused/complete; compact always-on-top runtime window that resizes itself to match the number of active drafts
- completion screen: shows typing/editing/total duration, donation options, share link, and quick reset for another run
- compatible everywhere: types into any macOS text field (Docs, Word, Notes, IDEs, browsers); prevents sleep during sessions; ESC pauses typing and stops editing
- privacy & localisation: no accounts or tracking; English, Simplified Chinese, and Traditional Chinese localisation
- updates & stack: Sparkle auto-updates; built with SwiftUI + AppKit (NSTextView), CoreGraphics CGEvent keyboard simulation, Accessibility APIs, and centralised logging

## Requirements

- macOS 14.6 or newer
- Accessibility permission enabled for Watch Me Type (required for keyboard simulation and focus tracking)

## Built with

- Swift and SwiftUI for the UI shell
- AppKit (NSTextView/NSScrollView via NSViewRepresentable) for native text editing with launch focus
- CoreGraphics (CGEvent) for keyboard event injection
- macOS Accessibility APIs for focus tracking, target-window locking, and the lazy permission flow
- a pure Swift diff engine (sentence and word-level LCS), shared between the right-to-left and left-to-right edit planners
- Sparkle for in-app updates
- centralised `os.log`-backed logging through the `appLog` global
- XCTest unit and integration tests covering the diff engine and the three-draft pipeline

## Architecture

Source layout under `Watch Me Type/`:

- `Watch_Me_TypeApp.swift` is the entry point. It configures Sparkle and hosts `ContentView`.
- `ContentView.swift` carries all UI: draft 1/2/3 editors, settings, overlays, the text-cleanup pipeline, and window management. The custom equal-width column layout, the fused edit-card and editor panels, and the auto-resizing window that adapts to the number of active drafts all live here.
- `TypingManager.swift` is the `ObservableObject` state machine (`idle → countingDown → typing → editing → paused`). It owns CGEvent injection, focus lock, sleep prevention, the ESC handler, and direction-aware edit execution. The Draft 2 path walks edits backward with backspaces; the Draft 3 path walks edits forward with shift-select-then-backspace and an offset accumulator. Before each destructive edit, the manager checks the live document against an internal snapshot and aborts on mismatch.
- `EditOperationConverter.swift` is the diff engine, kept deliberately pure: free functions only, no side effects, no imports beyond `Foundation`. A hybrid sentence and word-level LCS produces positioned edits, sortable right-to-left (`.rightToLeft`) or left-to-right (`.leftToRight`) via the `EditSortDirection` enum.
- `Logger.swift` wraps `os.Logger` in an `AppLogger` singleton with a six-level model: `none`, `error`, `warning`, `info`, `debug`, `verbose`. Always log through `appLog(_:level:)`.
- `AccessibilityPermissionHelper.swift` handles the lazy permission request, triggered from the in-app explanation screen rather than at launch.

The diff pipeline runs in five steps:

1. sentence tokenisation with abbreviation awareness (so "Dr.", "etc.", single initials, and embedded periods don't break sentence boundaries)
2. sentence pairing via Jaccard similarity
3. word-level LCS diff for pairs above `SIMILARITY_THRESHOLD = 0.4`, atomic sentence replace below it
4. word tokenisation that preserves whitespace tokens, so cursor positions stay accurate
5. position mapping into the source draft, followed by direction-aware sorting:
   - **Draft 1 → 2** (right-to-left): descending position. Edits apply without offset accumulation, because each edit's position is unaffected by edits already made further right.
   - **Draft 2 → 3** (left-to-right): ascending position. An offset accumulator nudges each subsequent edit's target position by the net length change of the preceding edits.

At execution time, the manager pauses about two seconds between phases, navigates with arrow keys (roughly 0.08s per press, 0.3s settle), and applies each edit either with a backspace run (backward) or with a shift-select-then-backspace (forward). Every destructive operation first verifies `expectedText` and `expectedOldText` against the tracked document snapshot, and aborts to `idle` if anything has drifted.

Tests under `Watch Me TypeTests/` cover `EditOperationConverter` (tokenisation, similarity, LCS, both sort directions) and the three-draft pipeline end to end. UI and CGEvent behaviour are not currently unit-tested.

## Installation

1. Download the DMG from [the latest release](https://github.com/0xff-r4bbit/watchmetype/releases/).
2. Drag **Watch Me Type** into the **Applications** folder.
3. Launch the app.
4. In the in-app prompt, choose **Continue** and grant Accessibility access in System Settings when prompted.
5. Sparkle will check for updates automatically after launch; manual "Check for Updates" is in the menu.

## Usage notes

- While the app is typing, the device is effectively unavailable; switching apps auto-pauses until you return. I would recommend running this in a VM.
- Provide Draft 2 to simulate a realistic revision of Draft 1; leave it blank for a single-draft run.
- Toggle "I have a draft 3." to chain a second revision pass that walks Draft 2 left-to-right into Draft 3 (useful when a single revision cycle isn't enough to look authentic).
- Use custom durations if you need a session to last a minimum amount of time; otherwise the app estimates based on WPM and text length.
- During any editing phase, focus or window changes abort editing to avoid writing in the wrong place. If that happens, use Cmd+Z in your target app.
- ESC pauses during typing, but stops editing sessions outright.

### Text cleanup behaviour

- Click **Process** to apply cleanup to Draft 1 and, if present, Draft 2 and Draft 3.
- Toggle-controlled cleanup includes removing blank lines, emojis, horizontal rules, bullet and numbered-list prefixes, and replacing em dashes with commas.
- Space normalisation (collapsing repeated spaces and removing spaces before punctuation) always runs during processing.

### Effective use

This app works best as part of a longer writing process. Generate drafts _elsewhere_, then use Watch Me Type to reproduce how writing normally appears over time (Draft 1) and, if needed, to stage a believable revision into Draft 2 and an optional polish pass into Draft 3.

## Build from source

```bash
xcodebuild -project "Watch Me Type.xcodeproj" -scheme "Watch Me Type" -destination 'platform=macOS' build
```

## Run tests

```bash
xcodebuild -project "Watch Me Type.xcodeproj" -scheme "Watch Me Type" -destination 'platform=macOS' test
```

## Contributing

Issues, pull requests, and feature suggestions are welcome.

## Supporting this project

Starring and sharing the project would help this reach educators and students who may benefit from it, either for their own work or as justification to rally for institutional change.

## Licence

This project is released under a source-available licence.

You are free to view, use, and modify the source code for personal and educational purposes. Commercial use, redistribution, hosting, or selling this software, including modified versions, is not permitted without explicit permission from the author.

The source is shared to support transparency, learning, and community discussion, not to enable resale or unauthorised distribution.

For details, see [LICENCE.md](LICENCE.md).
