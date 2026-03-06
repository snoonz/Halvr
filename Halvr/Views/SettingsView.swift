import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: ConverterViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Settings")
                .font(.headline)

            Form {
                Picker("Encoder", selection: $viewModel.settings.encoder) {
                    ForEach(EncoderType.allCases) { encoder in
                        Text(encoder.displayName).tag(encoder)
                    }
                }

                Picker("Quality", selection: $viewModel.settings.preset) {
                    ForEach(ExportPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Toggle("Preserve Original Timestamp", isOn: $viewModel.settings.preserveTimestamp)
            }
            .formStyle(.grouped)

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 280, height: 260)
        .onDisappear {
            viewModel.settings.save()
        }
    }
}
