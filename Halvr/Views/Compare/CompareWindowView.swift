import SwiftUI

struct CompareWindowView: View {
    let viewModel: ConverterViewModel
    @State private var controller: SyncedPlayerController?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let compareItem = viewModel.compareItem, let controller {
                CompareContentView(
                    compareItem: compareItem,
                    controller: controller
                )
            } else {
                emptyState
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .focusable()
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.compareItem, initial: true) { _, newItem in
            controller?.cleanup()
            if let newItem {
                controller = SyncedPlayerController(
                    originalURL: newItem.originalURL,
                    convertedURL: newItem.convertedURL
                )
            } else {
                controller = nil
            }
        }
        .onDisappear {
            controller?.cleanup()
            controller = nil
        }
        .onKeyPress(.space) {
            guard let controller else { return .ignored }
            controller.togglePlayPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            guard let controller else { return .ignored }
            controller.skip(by: -10)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard let controller else { return .ignored }
            controller.skip(by: 10)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard let controller else { return .ignored }
            controller.skip(by: -60)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard let controller else { return .ignored }
            controller.skip(by: 60)
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "qQ")) { _ in
            dismiss()
            return .handled
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No video selected for comparison")
                .foregroundStyle(.secondary)
        }
    }
}
