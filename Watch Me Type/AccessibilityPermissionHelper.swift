//
//  AccessibilityPermissionHelper.swift
//  Watch Me Type
//
//  Created by 0xff-r4bbit on 2025-12-03.
//

import Foundation
import ApplicationServices
import AppKit

enum AccessibilityPermissionHelper {
    /// Returns true if the app is alreasdy trusted for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask macOS for Accessibility permission.
    /// This will trigger the standard system prompt if the app isn't already trusted.
    static func requestIfNeeded() {
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]

        // This call returns immediately.
        // If not trusted, macOS shows the “allow this app to control your computer” prompt
        // the first time. After that, the user must manage it in System Settings.
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("AXIsProcessTrustedWithOptions returned: \(trusted)")
        if !trusted {
            // On newer macOS versions, the one-shot prompt may have already been shown
            // (and possibly dismissed). In that case, the only way to grant access is
            // via System Settings, so take the user directly to the Accessibility pane.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
