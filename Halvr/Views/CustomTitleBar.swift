import SwiftUI

struct CustomTitleBar: View {
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            Spacer()

            Text("Convert Video")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            settingsButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var settingsButton: some View {
        Button {
            showSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}
