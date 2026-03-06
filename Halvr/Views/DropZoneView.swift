import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let viewModel: ConverterViewModel
    let compact: Bool
    @State private var isTargeted = false

    private enum Layout {
        static let compactSpacing: CGFloat = 8
        static let normalSpacing: CGFloat = 16
        static let compactVerticalPadding: CGFloat = 4
        static let compactCornerRadius: CGFloat = 12
        static let normalCornerRadius: CGFloat = 16
        static let compactIconSize: CGFloat = 24
        static let normalIconSize: CGFloat = 40
        static let compactDropArea = CGSize(width: 220, height: 60)
        static let normalDropArea = CGSize(width: 180, height: 160)
    }

    var body: some View {
        VStack(spacing: compact ? Layout.compactSpacing : Layout.normalSpacing) {
            dropArea

            Text("Drag files or\nopen to convert")
                .multilineTextAlignment(.center)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(compact ? .horizontal : .all)
        .padding(.vertical, compact ? Layout.compactVerticalPadding : 0)
        .onTapGesture {
            viewModel.openFilePicker()
        }
    }

    private var dropArea: some View {
        let cornerRadius = compact ? Layout.compactCornerRadius : Layout.normalCornerRadius
        let iconSize = compact ? Layout.compactIconSize : Layout.normalIconSize
        let size = compact ? Layout.compactDropArea : Layout.normalDropArea

        return RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 2, dash: [8])
            )
            .foregroundStyle(isTargeted ? .white : .secondary)
            .overlay {
                Image(systemName: "arrow.down")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(isTargeted ? .white : .secondary)
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeInOut(duration: 0.2), value: isTargeted)
            .onDrop(
                of: [.fileURL],
                isTargeted: $isTargeted
            ) { providers in
                viewModel.handleDrop(providers: providers)
            }
    }
}
