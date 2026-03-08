import UniformTypeIdentifiers

enum SupportedFormats {
    static let mpeg2TransportStream = UTType("public.mpeg-2-transport-stream")!

    static let inputTypes: [UTType] = [
        .mpeg4Movie,
        .quickTimeMovie,
        .appleProtectedMPEG4Video,
        mpeg2TransportStream
    ]

    static let outputType: UTType = .mpeg4Movie

    static func isSupported(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return inputTypes.contains { type.conforms(to: $0) }
    }
}
