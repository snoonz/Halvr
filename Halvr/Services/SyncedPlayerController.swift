import AVFoundation
import Observation

@MainActor
@Observable
final class SyncedPlayerController {
    let originalPlayer: AVPlayer
    let convertedPlayer: AVPlayer

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    private var timeObserver: Any?
    private var syncTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    init(originalURL: URL, convertedURL: URL) {
        self.originalPlayer = AVPlayer(url: originalURL)
        self.convertedPlayer = AVPlayer(url: convertedURL)

        setupTimeObserver()
        setupEndObserver()
        loadDuration()
    }

    // MARK: - Lifecycle

    func cleanup() {
        if let timeObserver {
            originalPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        syncTask?.cancel()
        syncTask = nil
        pause()
    }

    // MARK: - Playback Control

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        originalPlayer.play()
        convertedPlayer.play()
        isPlaying = true
    }

    func pause() {
        originalPlayer.pause()
        convertedPlayer.pause()
        isPlaying = false
    }

    func stepForward() {
        pause()
        originalPlayer.currentItem?.step(byCount: 1)
        convertedPlayer.currentItem?.step(byCount: 1)
        syncCurrentTime()
    }

    func stepBackward() {
        pause()
        originalPlayer.currentItem?.step(byCount: -1)
        convertedPlayer.currentItem?.step(byCount: -1)
        syncCurrentTime()
    }

    func skip(by seconds: Double) {
        guard duration > 0 else { return }
        let newTime = min(max(currentTime + seconds, 0), duration)
        seek(to: newTime / duration)
    }

    func seek(to fraction: Double) {
        let targetTime = CMTime(seconds: fraction * duration, preferredTimescale: 600)
        let tolerance = CMTime.zero
        originalPlayer.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
        convertedPlayer.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
        currentTime = fraction * duration
    }

    // MARK: - Private

    private func setupTimeObserver() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = originalPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = CMTimeGetSeconds(time)
                self.syncFollower()
            }
        }
    }

    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: originalPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isPlaying = false
            }
        }
    }

    private func syncFollower() {
        let leaderTime = originalPlayer.currentTime()
        let followerTime = convertedPlayer.currentTime()
        let diff = abs(CMTimeGetSeconds(leaderTime) - CMTimeGetSeconds(followerTime))
        if diff > 0.05 {
            convertedPlayer.seek(
                to: leaderTime,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
    }

    private func syncCurrentTime() {
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            currentTime = CMTimeGetSeconds(originalPlayer.currentTime())
        }
    }

    private func loadDuration() {
        Task { @MainActor in
            guard let item = originalPlayer.currentItem else { return }
            do {
                let dur = try await item.asset.load(.duration)
                let seconds = CMTimeGetSeconds(dur)
                if seconds.isFinite {
                    duration = seconds
                }
            } catch {
                duration = 0
            }
        }
    }
}
