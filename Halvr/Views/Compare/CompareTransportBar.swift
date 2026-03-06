import SwiftUI

struct CompareTransportBar: View {
    let controller: SyncedPlayerController
    @Binding var showMetrics: Bool

    var body: some View {
        VStack(spacing: 8) {
            timelineSlider
            controlButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var timelineSlider: some View {
        HStack(spacing: 8) {
            Text(formattedTime(controller.currentTime))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { controller.seek(to: $0) }
                ),
                in: 0...1
            )

            Text(formattedTime(controller.duration))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 20) {
            Button(action: controller.stepBackward) {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Step Backward"))

            Button(action: controller.togglePlayPause) {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20)
            }
            .buttonStyle(.borderless)
            .help(controller.isPlaying
                  ? String(localized: "Pause")
                  : String(localized: "Play"))

            Button(action: controller.stepForward) {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Step Forward"))

            Spacer()

            Button {
                showMetrics.toggle()
            } label: {
                Image(systemName: showMetrics ? "info.circle.fill" : "info.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Quality Metrics"))
        }
    }

    private var sliderValue: Double {
        guard controller.duration > 0 else { return 0 }
        return controller.currentTime / controller.duration
    }

    private func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
