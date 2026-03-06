import SwiftUI

struct ContentView: View {
    @State private var viewModel = ConverterViewModel()
    @State private var showSettings = false

    private var hasQueueItems: Bool {
        !viewModel.queueItems.isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                CustomTitleBar(showSettings: $showSettings)

                if hasQueueItems {
                    DropZoneView(viewModel: viewModel, compact: true)
                        .padding(.top, 8)

                    Divider()
                        .padding(.vertical, 8)

                    QueueListView(viewModel: viewModel)
                } else {
                    Spacer()
                    DropZoneView(viewModel: viewModel, compact: false)
                    Spacer()
                }
            }
        }
        .frame(width: 280, height: 420)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}
