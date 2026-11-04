import SwiftUI

@main
struct MeowMailApp: App {
    @State private var store = AppStore(demo: ProcessInfo.processInfo.arguments.contains("-demo"))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.light)
                .tint(Theme.accent)
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await store.syncIfDue()
                        try? await Task.sleep(for: .seconds(AppStore.syncInterval))
                    }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}
