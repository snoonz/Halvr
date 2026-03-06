import SwiftUI

struct QueueListView: View {
    let viewModel: ConverterViewModel
    @Environment(\.openWindow) private var openWindow

    private var hasFinishedItems: Bool {
        viewModel.queueItems.contains { item in
            switch item.status {
            case .completed, .skipped:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.queueItems) { item in
                        QueueItemRow(
                            item: item,
                            onRemove: { viewModel.removeItem(id: item.id) },
                            onCompare: {
                                viewModel.requestCompare(for: item)
                                openWindow(id: "compare")
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }

            if hasFinishedItems || viewModel.isProcessing {
                Divider()
                    .padding(.top, 4)

                HStack(spacing: 12) {
                    if viewModel.isProcessing {
                        Button("Cancel") {
                            viewModel.cancelConversion()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }

                    if hasFinishedItems {
                        Button("Clear") {
                            viewModel.clearCompleted()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}

private struct QueueItemRow: View {
    let item: QueueItem
    let onRemove: () -> Void
    let onCompare: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            statusIcon

            Text(item.filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            statusLabel
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .cornerRadius(6)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .pending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .converting:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .skipped:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.yellow)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch item.status {
        case .pending:
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        case .converting(let progress):
            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .completed:
            Button(action: onCompare) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Compare"))
        case .skipped(let error):
            Text(error.title)
                .font(.caption2)
                .foregroundStyle(.yellow)
        }
    }

    private var rowBackground: Color {
        switch item.status {
        case .converting:
            return Color.white.opacity(0.05)
        default:
            return Color.clear
        }
    }
}
