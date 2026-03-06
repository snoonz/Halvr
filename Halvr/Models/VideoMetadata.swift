import CoreMedia
import Foundation

struct VideoMetadata: Equatable {
    let duration: CMTime
    let resolution: CGSize
    let codec: String
    let fileSize: Int64
    let bitrate: Int64
    let isAlreadyHEVC: Bool

    var formattedDuration: String {
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite else { return "--:--" }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    var formattedResolution: String {
        "\(Int(resolution.width))x\(Int(resolution.height))"
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedBitrate: String {
        let mbps = Double(bitrate) / 1_000_000
        return String(format: "%.1f Mbps", mbps)
    }
}
