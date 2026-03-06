import AVFoundation
import Foundation

protocol VideoMetadataReading: Sendable {
    func read(from url: URL) async throws -> VideoMetadata
}

struct VideoMetadataReader: VideoMetadataReading {
    func read(from url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTrack = try await asset.loadTracks(withMediaType: .video).first

        let trackInfo = try await extractTrackInfo(from: videoTrack)

        let fileSize = (try? FileManager.default.attributesOfItem(
            atPath: url.path
        )[.size] as? Int64) ?? 0

        let bitrate = computeBitrate(
            estimatedBitrate: trackInfo.estimatedBitrate,
            fileSize: fileSize,
            durationSeconds: CMTimeGetSeconds(duration)
        )

        return VideoMetadata(
            duration: duration,
            resolution: trackInfo.resolution,
            codec: trackInfo.codec,
            fileSize: fileSize,
            bitrate: bitrate,
            isAlreadyHEVC: trackInfo.isHEVC
        )
    }

    private func extractTrackInfo(
        from track: AVAssetTrack?
    ) async throws -> (resolution: CGSize, codec: String, isHEVC: Bool, estimatedBitrate: Float) {
        guard let track else {
            return (.zero, "unknown", false, 0)
        }

        let size = try await track.load(.naturalSize)
        let descriptions = try await track.load(.formatDescriptions)
        let codecType = descriptions.first.map {
            CMFormatDescriptionGetMediaSubType($0 as CMFormatDescription)
        }
        let codec = codecType.map(Self.codecFourCC) ?? "unknown"
        let estimatedBitrate = try await track.load(.estimatedDataRate)

        return (size, codec, codecType == kCMVideoCodecType_HEVC, estimatedBitrate)
    }

    private static func codecFourCC(from fourCC: FourCharCode) -> String {
        var chars: [Character] = []
        for i in 0..<4 {
            let byte = (fourCC >> (24 - i * 8)) & 0xFF
            if let scalar = UnicodeScalar(byte) {
                chars.append(Character(scalar))
            }
        }
        return String(chars)
    }

    private func computeBitrate(
        estimatedBitrate: Float,
        fileSize: Int64,
        durationSeconds: Double
    ) -> Int64 {
        if estimatedBitrate > 0 {
            return Int64(estimatedBitrate)
        } else if durationSeconds > 0, durationSeconds.isFinite {
            return (fileSize * 8) / Int64(durationSeconds)
        }
        return 0
    }
}
