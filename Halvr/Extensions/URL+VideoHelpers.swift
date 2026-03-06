import Foundation
import UniformTypeIdentifiers

extension URL {
    var isVideoFile: Bool {
        SupportedFormats.isSupported(self)
    }

    var hevcOutputURL: URL {
        OutputPathResolver.resolve(inputURL: self, outputDirectory: nil)
    }
}
