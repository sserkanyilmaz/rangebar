import SwiftUI

@main
struct RangeBarApp: App {
    @State private var store    = PositionStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            Image(systemName: "water.waves")
        }
        .menuBarExtraStyle(.window)
    }
}
