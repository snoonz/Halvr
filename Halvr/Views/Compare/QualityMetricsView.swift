import SwiftUI

struct QualityMetricsView: View {
    let url: URL
    @State private var metadata: VideoMetadata?

    var body: some View {
        Group {
            if let metadata {
                metricsContent(metadata)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 120, height: 60)
            }
        }
        .task(id: url) {
            await loadMetadata()
        }
    }

    private func metricsContent(_ meta: VideoMetadata) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            metricRow(String(localized: "Size"), meta.formattedFileSize)
            metricRow(String(localized: "Bitrate"), meta.formattedBitrate)
            metricRow(String(localized: "Resolution"), meta.formattedResolution)
            metricRow(String(localized: "Codec"), meta.codec)
        }
        .font(.caption2)
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(minWidth: 140)
    }

    private func loadMetadata() async {
        let reader = VideoMetadataReader()
        metadata = try? await reader.read(from: url)
    }
}
