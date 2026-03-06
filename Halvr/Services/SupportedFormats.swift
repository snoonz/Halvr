import UniformTypeIdentifiers

enum SupportedFormats {
    static let inputTypes: [UTType] = [
        .mpeg4Movie,
        .quickTimeMovie,
        .appleProtectedMPEG4Video
    ]

    static let outputType: UTType = .mpeg4Movie

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return inputTypes.contains { type.conforms(to: $0) }
    }
}
