import SwiftUI

@main
struct Watch_Me_TypeApp: App {

    init() {
        // Ask for Accessibility at launch if needed.
        AccessibilityPermissionHelper.requestIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
