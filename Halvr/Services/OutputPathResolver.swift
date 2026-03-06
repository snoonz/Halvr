import Foundation

enum OutputPathResolver {
    static func resolve(
        inputURL: URL,
        outputDirectory: URL?
    ) -> URL {
        let directory = outputDirectory ?? inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputName = "\(baseName)_HEVC.mp4"
        let outputURL = directory.appendingPathComponent(outputName)

        return uniqueURL(for: outputURL)
    }

    private static let maxSuffixAttempts = 1000

    private static func uniqueURL(for url: URL) -> URL {
        var candidate = url
        var counter = 1

        while FileManager.default.fileExists(atPath: candidate.path), counter <= maxSuffixAttempts {
            let directory = url.deletingLastPathComponent()
            let baseName = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            candidate = directory.appendingPathComponent(
                "\(baseName)_\(counter).\(ext)"
            )
            counter += 1
        }

        return candidate
    }
}
