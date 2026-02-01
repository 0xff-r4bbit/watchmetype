# Watch Me Type

_because revision history is not learning_

Watch Me Type is an open-source macOS app that types text into any active window with the pacing, pauses, and imperfections of a real person. It can replay a single draft or stage a Draft 1 → Draft 2 revision, locking to the chosen window, auto-pausing on focus changes, and running for the exact duration you need.

## Purpose

> TL;DR: to force those in charge in education to empower teachers with the resources to adapt to the ubiquity of AI

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
- two modes: single-draft typing or two-phase draft1→draft2 editing that rewrites the first draft with cursor-accurate edits and navigation delays
- duration control: auto-estimated or custom minimum typing/editing times with live progress tracking and a 10-second countdown
- text clean-up toggles: remove blank lines/emojis/bullets/horizontal rules, replace em-dashes, collapse extra spaces, and fix spacing before punctuation
- focus-aware: locks to the chosen window, auto-pauses on app switch, auto-resumes when you return, overlays for countdown/typing/thinking/editing/paused/complete, minimizes the main window while running
- completion screen: shows typing/editing/total duration, donation options, share link, and quick reset for another run
- compatible everywhere: types into any macOS text field (Docs, Word, Notes, IDEs, browsers); prevents sleep during sessions; ESC pauses/stops
- privacy & localization: no accounts or tracking; English plus Chinese localization
- updates & stack: Sparkle auto-updates; built with SwiftUI + AppKit (NSTextView), CoreGraphics CGEvent keyboard simulation, Accessibility APIs, and centralized logging

## Built With

- Swift + SwiftUI
- AppKit (NSTextView) for native text editing
- CoreGraphics (CGEvent) for keyboard simulation
- macOS Accessibility APIs for focus tracking and window control
- Sparkle for in-app updates
- Centralized logging for debugging sessions

## Installation

1. Download [the DMG from the latest release](https://github.com/0xff-r4bbit/watchmetype/releases/latest/download/WatchMeType.dmg).
2. Drag **Watch Me Type** into the **Applications** folder.
3. Launch the app.
4. When macOS asks, grant Accessibility access (required to type for you).
5. Sparkle will check for updates automatically after launch; manual “Check for Updates” is in the menu.

## Usage Notes

- While the app is typing, the device is effectively unavailable; switching apps auto-pauses until you return.
- Provide Draft 2 to simulate a realistic revision of Draft 1; leave it blank for a single-draft run.
- Use custom durations if you need a session to last a minimum amount of time; otherwise the app estimates based on WPM and text length.
- Do not complete an entire piece of writing in a single session if the goal is a realistic revision history.

### Effective Use

This app works best as part of a longer writing process. Generate drafts _elsewhere_, then use Watch Me Type to reproduce how writing normally appears over time (Draft 1) and, if needed, to stage a believable edit into Draft 2.

When generating drafts, use a prompt like the one below. Replace bracketed text as needed.

```
Create a plan for the sections required for this [assignment / project / journal]. We will complete the sections one by one.

For each section, produce two exemplars:
- one written in B2-level [Canadian / American / British] English
- one written in C2-level English

The B2-level draft should include grammar and usage errors typical of a B2-level English speaker. Avoid stylistic and other linguistic patterns and features identified in AI-generated writing, as detailed in "signs"-of-ai-writing.jpeg”.
```

## Screenshots

<p align="center">
    <img src="assets/screenshots/main.png" alt="main window"><br>
    <em>main app window</em>
</p><br>
<p align="center">
    <img src="assets/screenshots/accessibility.png" alt="macOS Accessibility permission prompt"><br>
    <em>macOS Accessibility permission prompt</em>
</p><br>
<p align="center">
    <img src="assets/screenshots/typing.png" alt="typing in progress"><br>
    <em>typing in progress</em>
</p><br>
<p align="center">
    <img src="assets/screenshots/completed.png" alt="completed session"><br>
    <em>completed session</em>
</p>

## Contributing

Issues, pull requests, and feature suggestions are welcome.

## Supporting this Project

Starring and sharing the project would help this reach educators and students who may benefit from it, either for their own work or as justification to rally for institutional change.

## Licence

This project is released under a source-available licence.

You are free to view, use, and modify the source code for personal and educational purposes. Commercial use, redistribution, hosting, or selling this software, including modified versions, is not permitted without explicit permission from the author.

The source is shared to support transparency, learning, and community discussion, not to enable resale or unauthorised distribution.

For details, see [licence.md](licence.md).
