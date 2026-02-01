# Watch Me Type - Feature Reference

This document provides a comprehensive overview of the "Watch Me Type" macOS application for LLMs and documentation writers.

## Overview

**Watch Me Type** is an open-source macOS application that simulates human-like typing into any active window. It types text with realistic delays, thinking pauses, and intentional mistakes to recreate the appearance of genuine writing over time rather than instant text generation.

### Target Use Case

The app is designed for students facing institutional pressures around AI-generated content detection. It exposes the problem with institutional reliance on "process forensics" (revision history, typing patterns) rather than evaluating actual learning and skill growth.

### Key Principles

- No accounts, tracking, or analytics
- Open source (GitHub hosted)
- Works with any macOS text input field (browsers, Google Docs, Word, Notes, code editors, etc.)

---

## Core Features

### Typing Modes

| Mode                          | Description                                                                              |
| ----------------------------- | ---------------------------------------------------------------------------------------- |
| **Single-Draft Mode**         | Types a single piece of text with human-like behavior                                    |
| **Two-Phase/Dual-Draft Mode** | Types Draft 1, then edits it to transform into Draft 2 (simulating the revision process) |

### Human-Like Typing Simulation

The app simulates realistic human typing behavior through:

- **Adjustable typing speed**: 40-120 WPM (default: 80 WPM)
- **Random thinking pauses**: Every 3-5 words (1-2 seconds)
- **Comma pauses**: 1-2 seconds at commas
- **Sentence ending pauses**: 5-10 seconds at periods/question marks/exclamation points
- **Paragraph pauses**: 6-12 seconds between paragraph breaks
- **Transition word pauses**: Brief pause before words like "however", "nevertheless", "because", etc.
- **Intentional mistakes**: Types wrong character, pauses 3 seconds, then corrects with backspace

### Duration Control

- Automatic duration estimation based on WPM and character count
- Custom total typing duration option (specify minimum time in minutes or hours)
- For editing phase: automatic or custom duration specification
- Real-time progress tracking with percentage completion

---

## Text Pre-Processing Options

Before typing begins, users can clean up their text with these toggles:

| Option                           | Description                             |
| -------------------------------- | --------------------------------------- |
| Remove blank lines               | Strips empty lines from text            |
| Remove emojis                    | Strips emoji characters                 |
| Remove horizontal rules          | Removes lines like `----`, `====`, etc. |
| Remove bullet points             | Removes `-` and `•` prefixes            |
| Replace em-dashes                | Converts `—` to commas                  |
| Collapse multiple spaces         | Automatically applied                   |
| Remove spaces before punctuation | Automatically applied                   |

---

## Window Focus Management

The app includes sophisticated focus tracking:

- **Records target window** at start of typing session
- **Auto-pause**: Automatically pauses if user switches away from target window
- **Auto-resume**: Resumes when user returns to original window
- **Progress overlay**: Displays typing status, progress bar, and instructions
- **10-second countdown** before typing begins
- **Window minimization**: Main window minimizes during typing and restores after completion

---

## Two-Phase Editing (Draft 1 → Draft 2)

When Draft 2 is provided, the app simulates a realistic revision process:

### Algorithm

- **Hybrid edit approach**: Uses sentence-level analysis for major changes and word-level diffing for minor changes
- **Similarity threshold**: Determines edit strategy based on Jaccard similarity
- **Backwards editing**: Navigates backward through document, makes changes right-to-left, then simulates re-reading

### Editing Behavior

- Tracks cursor position accurately through all edits
- Includes navigation delays (moving cursor with arrow keys)
- Includes operation delays between edits
- Uses forward delete, backspace, and text insertion

---

## User Interface Components

### Main Window Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Header: Title, description, GitHub link, support buttons   │
├─────────────────────────────────────────────┬───────────────┤
│                                             │               │
│  Draft 1 Editor     │  Draft 2 Editor       │   Settings    │
│  (required)         │  (optional)           │   Panel       │
│                     │                       │   (320px)     │
│                     │                       │               │
├─────────────────────┴───────────────────────┴───────────────┤
│                      Start Button                           │
└─────────────────────────────────────────────────────────────┘
```

### Settings Panel Cards

1. **Clean-Up Card**: Text preprocessing toggles + "Process" button
2. **Typing Speed Card**: WPM slider (40-120), estimated duration, custom duration toggle
3. **Editing Phase Card** (when Draft 2 provided): Custom editing duration toggle

### Overlay States

| State     | Background | Content                                              |
| --------- | ---------- | ---------------------------------------------------- |
| Countdown | Black 70%  | 10-second timer                                      |
| Typing    | Black 70%  | "Typing" status, progress bar, percentage            |
| Thinking  | Black 70%  | "Thinking" status during pauses                      |
| Editing   | Black 70%  | "Editing" status, progress, phase indicator          |
| Paused    | Black 70%  | "Paused" status, instructions to switch back         |
| Complete  | White      | "Done" message, duration breakdown, donation options |

### Completion Screen

- Large "Done" message
- Duration breakdown (typing phase, editing phase, total)
- Donation options:
  - Ko-fi button with QR code
  - WeChat Pay button with modal QR overlay
- "Share this app" button (copies GitHub URL)
- "Let's go again" button (reset for next session)

---

## Technical Architecture

### Technology Stack

| Component           | Technology                                            |
| ------------------- | ----------------------------------------------------- |
| UI Framework        | SwiftUI                                               |
| Native Text Editing | AppKit (NSTextView via NSViewRepresentable)           |
| Keyboard Simulation | CoreGraphics (CGEvent)                                |
| Window Management   | AppKit (NSWorkspace, NSWindow)                        |
| Focus Tracking      | ApplicationServices (Accessibility API / AXUIElement) |
| Auto-Updates        | Sparkle Framework                                     |

### Key Source Files

| File                                  | Purpose                                            | ~Lines |
| ------------------------------------- | -------------------------------------------------- | ------ |
| `Watch_Me_TypeApp.swift`              | App entry point, Sparkle updater setup             | 30     |
| `ContentView.swift`                   | Main UI, editors, settings, overlays               | 1460   |
| `TypingManager.swift`                 | Core typing engine, state machine, keyboard events | 1740   |
| `EditOperationConverter.swift`        | Diff algorithm, edit operation generation          | 558    |
| `AccessibilityPermissionHelper.swift` | Permission checking and requesting                 | 40     |
| `Logger.swift`                        | Centralized logging system                         | 92     |

### State Machine

The TypingManager uses these states:

```
idle → countingDown → typing → editing → idle
                        ↓         ↓
                     paused    paused
```

### Keyboard Event Generation

- Uses CGEvent with UTF-16 unicode string encoding
- Special key codes:
  - Backspace: `0x33`
  - Forward Delete: `0x75`
  - Return: `0x24`
  - Escape: `0x35`
  - Arrow keys for navigation
- CGEventTap for global ESC key detection (pause/stop)

### Focus Tracking Strategy

1. Records target app PID and window title at typing start
2. Uses Accessibility API (AXUIElement) to query current focused window
3. Periodic focus check timer (0.5-second intervals) as safety net
4. Handles app switching via NSWorkspace notifications
5. Per-character and per-edit focus verification

---

## System Integration

### Required Permissions

- **Accessibility**: Required to control keyboard for typing simulation
- First launch shows explanation dialog
- Opens System Settings if permission not granted

### macOS Features Used

- Accessibility permissions (System Settings controlled)
- Window level management (always-on-top during typing)
- System idle sleep prevention during active sessions
- Global event taps for ESC key
- Frontmost application tracking
- Workspace notifications

### Auto-Updates (Sparkle)

- Feed URL: `https://0xff-r4bbit.github.io/watchmetype/appcast.xml`
- Secure updates with ED public key verification
- Automatic check on launch
- Manual "Check for Updates" menu command

---

## Localization

- Primary language: English
- Chinese localization support (mentioned in recent commits)
- Chinese payment option (WeChat Pay) included
- UI text is in SwiftUI views (prepared for internationalization)

---

## Error Handling

| Scenario                        | Behavior                                                    |
| ------------------------------- | ----------------------------------------------------------- |
| Focus lost during typing        | Auto-pauses, can resume by returning to window              |
| Focus lost during editing       | Immediately terminates with user-friendly error alert       |
| Accessibility permission denied | Shows dialog with instructions to enable in System Settings |
| ESC key pressed                 | Pauses/stops current operation                              |

---

## Session-Based Settings

All settings are per-session (not persisted):

- WPM (40-120)
- Text processing toggles (6 options)
- Custom typing duration (minutes or hours)
- Custom editing duration (minutes or hours)
- Draft 2 content for two-phase mode

---

## External Integrations

| Integration | Purpose                         |
| ----------- | ------------------------------- |
| GitHub      | Source code repository, sharing |
| Ko-fi       | Donation platform               |
| WeChat Pay  | Chinese donation option         |
| Sparkle     | Auto-update framework           |

---

## Compatibility

- **Platform**: macOS only
- **Text Targets**: Any application with text input (browsers, document editors, IDEs, notes apps, etc.)
- **Input Types**: Both rich text and plain text contexts supported
