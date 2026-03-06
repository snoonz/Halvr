import AVFoundation
import SwiftUI

struct CompareContentView: View {
    let compareItem: CompareItem
    let controller: SyncedPlayerController
    @State private var showMetrics = false

    var body: some View {
        VStack(spacing: 0) {
            videoArea
            CompareTransportBar(
                controller: controller,
                showMetrics: $showMetrics
            )
        }
        .background(Color.black)
    }

    private var videoArea: some View {
        HStack(spacing: 1) {
            videoPanel(
                label: String(localized: "Original"),
                filename: compareItem.originalFilename,
                player: controller.originalPlayer,
                url: compareItem.originalURL,
                showMetrics: showMetrics
            )

            videoPanel(
                label: String(localized: "Converted (HEVC)"),
                filename: compareItem.convertedFilename,
                player: controller.convertedPlayer,
                url: compareItem.convertedURL,
                showMetrics: showMetrics
            )
        }
    }

    private func videoPanel(
        label: String,
        filename: String,
        player: AVPlayer,
        url: URL,
        showMetrics: Bool
    ) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(filename)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 6)

            ZStack {
                PlayerView(player: player)

                if showMetrics {
                    VStack {
                        Spacer()
                        QualityMetricsView(url: url)
                            .padding(8)
                    }
                }
            }
        }
    }
}
