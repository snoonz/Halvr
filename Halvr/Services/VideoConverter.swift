import AVFoundation
import Foundation
import os

enum ConversionError: LocalizedError {
    case inputFileNotReadable
    case noVideoTrack
    case exportFailed(String)
    case alreadyHEVC
    case cancelled
    case ffmpegNotFound

    var errorDescription: String? {
        switch self {
        case .inputFileNotReadable:
            return String(localized: "Cannot read input video file.")
        case .noVideoTrack:
            return String(localized: "No video track found.")
        case .exportFailed(let reason):
            return String(localized: "Export failed: \(reason)")
        case .alreadyHEVC:
            return String(localized: "This video is already encoded in HEVC.")
        case .cancelled:
            return String(localized: "Conversion was cancelled.")
        case .ffmpegNotFound:
            return String(localized: "ffmpeg not found. Install via Homebrew: brew install ffmpeg")
        }
    }
}

protocol VideoConverting: Sendable {
    func convert(
        inputURL: URL,
        outputURL: URL,
        settings: ConversionSettings,
        metadata: VideoMetadata,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL

    func cancel()
}

final class FFmpegConverter: VideoConverting, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    private struct State {
        var currentProcess: Process?
        var isCancelled = false
    }

    private static let ffmpegSearchPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
    ]

    func convert(
        inputURL: URL,
        outputURL: URL,
        settings: ConversionSettings,
        metadata: VideoMetadata,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        lock.withLock { state in
            state.isCancelled = false
            state.currentProcess = nil
        }

        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw ConversionError.inputFileNotReadable
        }

        let totalDurationSeconds = CMTimeGetSeconds(metadata.duration)
        guard totalDurationSeconds > 0 else {
            throw ConversionError.exportFailed(String(localized: "Cannot get video duration."))
        }

        let ffmpegPath = try resolveFFmpegPath()
        let arguments = buildArguments(
            inputURL: inputURL,
            outputURL: outputURL,
            settings: settings
        )

        return try await runFFmpeg(
            executablePath: ffmpegPath,
            arguments: arguments,
            outputURL: outputURL,
            totalDurationSeconds: totalDurationSeconds,
            progressHandler: progressHandler
        )
    }

    func cancel() {
        lock.withLock { state in
            state.isCancelled = true
            state.currentProcess?.interrupt()
        }
    }

    private func resolveFFmpegPath() throws -> String {
        for path in Self.ffmpegSearchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw ConversionError.ffmpegNotFound
    }

    private func buildArguments(
        inputURL: URL,
        outputURL: URL,
        settings: ConversionSettings
    ) -> [String] {
        ["-nostdin", "-i", inputURL.path, "-c:v", settings.encoder.ffmpegCodec]
            + settings.preset.qualityArguments(for: settings.encoder)
            + ["-c:a", "copy", "-tag:v", "hvc1", "-y", outputURL.path]
    }

    private func runFFmpeg(
        executablePath: String,
        arguments: [String],
        outputURL: URL,
        totalDurationSeconds: Double,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { rawContinuation in
            let continuation = SafeContinuation(rawContinuation)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice

            let stderrPipe = Pipe()
            process.standardError = stderrPipe

            lock.withLock { $0.currentProcess = process }

            let stderrBuffer = OSAllocatedUnfairLock<Data>(initialState: Data())
            let residualLock = OSAllocatedUnfairLock<String>(initialState: "")

            configureStderrHandler(
                pipe: stderrPipe,
                stderrBuffer: stderrBuffer,
                residualLock: residualLock,
                totalDurationSeconds: totalDurationSeconds,
                progressHandler: progressHandler
            )

            configureTerminationHandler(
                process: process,
                stderrPipe: stderrPipe,
                stderrBuffer: stderrBuffer,
                outputURL: outputURL,
                continuation: continuation
            )

            do {
                try process.run()
            } catch {
                cleanupPartialFile(at: outputURL)
                continuation.resume(
                    throwing: ConversionError.exportFailed(String(localized: "Failed to start ffmpeg: \(error.localizedDescription)"))
                )
            }
        }
    }

    private func configureStderrHandler(
        pipe: Pipe,
        stderrBuffer: OSAllocatedUnfairLock<Data>,
        residualLock: OSAllocatedUnfairLock<String>,
        totalDurationSeconds: Double,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) {
        let timePattern = /time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})/

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            stderrBuffer.withLock { $0.append(data) }

            guard let chunk = String(data: data, encoding: .utf8) else { return }

            let fullText = residualLock.withLock { residual in
                let combined = residual + chunk
                return combined
            }

            let segments = fullText.components(separatedBy: "\r")
            residualLock.withLock { $0 = segments.last ?? "" }

            for segment in segments.dropLast() {
                if let match = segment.firstMatch(of: timePattern) {
                    let currentSeconds = Self.parseTimeMatch(match)
                    let progress = min(currentSeconds / totalDurationSeconds, 0.99)
                    progressHandler(progress)
                }
            }
        }
    }

    private func configureTerminationHandler(
        process: Process,
        stderrPipe: Pipe,
        stderrBuffer: OSAllocatedUnfairLock<Data>,
        outputURL: URL,
        continuation: SafeContinuation<URL>
    ) {
        process.terminationHandler = { [weak self] terminatedProcess in
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            let status = terminatedProcess.terminationStatus
            let isCancelled = self?.lock.withLock { $0.isCancelled } ?? false

            if isCancelled || terminatedProcess.terminationReason == .uncaughtSignal {
                self?.cleanupPartialFile(at: outputURL)
                continuation.resume(throwing: ConversionError.cancelled)
                return
            }

            if status == 0 {
                continuation.resume(returning: outputURL)
                return
            }

            let stderrData = stderrBuffer.withLock { $0 }
            let stderrOutput = String(data: stderrData, encoding: .utf8) ?? String(localized: "Unknown error")
            let lastLines = stderrOutput
                .components(separatedBy: .newlines)
                .suffix(5)
                .joined(separator: "\n")
            self?.cleanupPartialFile(at: outputURL)
            continuation.resume(throwing: ConversionError.exportFailed(lastLines))
        }
    }

    private static func parseTimeMatch(
        _ match: Regex<(Substring, Substring, Substring, Substring, Substring)>.Match
    ) -> Double {
        let hours = Double(match.1) ?? 0
        let minutes = Double(match.2) ?? 0
        let seconds = Double(match.3) ?? 0
        let centiseconds = Double(match.4) ?? 0
        return hours * 3600 + minutes * 60 + seconds + centiseconds / 100.0
    }

    private func cleanupPartialFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class SafeContinuation<T>: Sendable where T: Sendable {
    private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)
    private nonisolated(unsafe) let continuation: CheckedContinuation<T, Error>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        guard lock.withLock({ let was = $0; $0 = true; return !was }) else { return }
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        guard lock.withLock({ let was = $0; $0 = true; return !was }) else { return }
        continuation.resume(throwing: error)
    }
}
