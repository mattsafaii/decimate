import SwiftUI

@main
struct DecimateApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(state: appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") {
                    appState.isImporterPresented = true
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
