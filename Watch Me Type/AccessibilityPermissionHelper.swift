//
//  AccessibilityPermissionHelper.swift
//  Watch Me Type
//
//  Created by 0xff-r4bbit on 2025-12-03.
//

import Foundation
import ApplicationServices

enum AccessibilityPermissionHelper {
    /// Returns true if the app is already trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask macOS for Accessibility permission if we don't have it yet.
    /// This will trigger the standard system prompt.
    static func requestIfNeeded() {
        // If already trusted, do nothing.
        if AXIsProcessTrusted() {
            return
        }

        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]

        // This call returns immediately.
        // If not trusted, macOS shows the “allow this app to control your computer” prompt.
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
