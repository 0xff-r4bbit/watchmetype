import SwiftUI
import ApplicationServices

@main
struct Watch_Me_TypeApp: App {

    init() {
        // Debug: log bundle ID and accessibility trust at launch.
        print("Bundle ID:", Bundle.main.bundleIdentifier ?? "nil")
        print("Trusted at launch?", AXIsProcessTrusted())

        // Ask for Accessibility at launch if needed.
        AccessibilityPermissionHelper.requestIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
