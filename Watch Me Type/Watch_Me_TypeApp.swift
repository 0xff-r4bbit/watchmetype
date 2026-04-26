import SwiftUI
import ApplicationServices
import Sparkle

@main
struct Watch_Me_TypeApp: App {

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    init() {
        // Accessibility permission is now requested after an in-app explanation
        // from the main UI, instead of immediately at launch.
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1000, height: 840)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
            }
        }
    }
}
