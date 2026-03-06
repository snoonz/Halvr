import SwiftUI

@main
struct HalvrApp: App {
    @State private var viewModel = ConverterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 280, height: 420)

        Window("Compare", id: "compare") {
            CompareWindowView(viewModel: viewModel)
        }
        .defaultSize(width: 960, height: 540)
    }
}
