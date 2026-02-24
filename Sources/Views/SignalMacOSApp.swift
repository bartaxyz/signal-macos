import SwiftUI

@main
struct SignalMacOSApp: App {
    @State private var store = SignalStore()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if store.isLinked {
                    ContentView()
                } else {
                    LinkDeviceView()
                }
            }
            .environment(store)
        }
        .windowStyle(.titleBar)
    }
}
