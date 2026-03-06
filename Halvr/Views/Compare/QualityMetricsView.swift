import SwiftUI

struct QualityMetricsView: View {
    let url: URL
    @State private var metadata: VideoMetadata?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let metadata {
                metricsContent(metadata)
            } else if loadFailed {
                failedContent
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var failedContent: some View {
        Text("--")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
        do {
            metadata = try await reader.read(from: url)
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }
}
