import Foundation

struct ConversionSettings: Equatable {
    var preset: ExportPreset
    var encoder: EncoderType
    var preserveTimestamp: Bool
    let outputDirectory: URL?

    static let `default` = ConversionSettings(
        preset: .highQuality,
        encoder: .videotoolbox,
        preserveTimestamp: true,
        outputDirectory: nil
    )

    private enum Keys {
        static let encoder = "settings.encoder"
        static let preset = "settings.preset"
        static let preserveTimestamp = "settings.preserveTimestamp"
    }

    static func load() -> ConversionSettings {
        let defaults = UserDefaults.standard
        let encoder = defaults.string(forKey: Keys.encoder)
            .flatMap(EncoderType.init(rawValue:)) ?? .videotoolbox
        let preset = defaults.string(forKey: Keys.preset)
            .flatMap(ExportPreset.init(rawValue:)) ?? .highQuality
        let preserveTimestamp = defaults.object(forKey: Keys.preserveTimestamp) as? Bool ?? true
        return ConversionSettings(
            preset: preset,
            encoder: encoder,
            preserveTimestamp: preserveTimestamp,
            outputDirectory: nil
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(encoder.rawValue, forKey: Keys.encoder)
        defaults.set(preset.rawValue, forKey: Keys.preset)
        defaults.set(preserveTimestamp, forKey: Keys.preserveTimestamp)
    }
}

enum EncoderType: String, CaseIterable, Identifiable, Sendable {
    case videotoolbox
    case libx265

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .videotoolbox:
            return String(localized: "Hardware (Fast)")
        case .libx265:
            return String(localized: "Software (High Quality)")
        }
    }

    var ffmpegCodec: String {
        switch self {
        case .videotoolbox:
            return "hevc_videotoolbox"
        case .libx265:
            return "libx265"
        }
    }
}

enum ExportPreset: String, CaseIterable, Identifiable, Sendable {
    case highQuality
    case standard
    case smallSize

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .highQuality:
            return String(localized: "High Quality")
        case .standard:
            return String(localized: "Standard")
        case .smallSize:
            return String(localized: "Small Size")
        }
    }

    private enum VideoToolboxQuality {
        static let high = "78"
        static let standard = "65"
        static let small = "55"
    }

    private enum X265CRF {
        static let high = "23"
        static let standard = "28"
        static let small = "32"
    }

    func qualityArguments(for encoder: EncoderType) -> [String] {
        switch encoder {
        case .videotoolbox:
            let quality: String = switch self {
            case .highQuality: VideoToolboxQuality.high
            case .standard: VideoToolboxQuality.standard
            case .smallSize: VideoToolboxQuality.small
            }
            return ["-q:v", quality]
        case .libx265:
            let crf: String = switch self {
            case .highQuality: X265CRF.high
            case .standard: X265CRF.standard
            case .smallSize: X265CRF.small
            }
            return ["-crf", crf, "-preset", "medium"]
        }
    }
}
