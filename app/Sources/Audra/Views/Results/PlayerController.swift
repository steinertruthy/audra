import AVFoundation
import Observation

/// Owns the AVPlayer for one recording and publishes the playhead for transcript syncing.
@MainActor
@Observable
final class PlayerController {
    let player: AVPlayer
    private(set) var currentTime: Double = 0
    private(set) var isPlaying = false

    var rate: Float = 1 {
        didSet { if isPlaying { player.rate = rate } }
    }

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var rateObservation: NSKeyValueObservation?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                let seconds = time.seconds
                if seconds.isFinite { self?.currentTime = seconds }
            }
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            let playing = player.rate != 0
            Task { @MainActor in self?.isPlaying = playing }
        }
    }

    func invalidate() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        rateObservation?.invalidate()
    }

    func seek(to seconds: Double, play: Bool = false) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        currentTime = max(0, seconds)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 0.1, preferredTimescale: 600))
        if play && !isPlaying { player.playImmediately(atRate: rate) }
    }

    func togglePlayback() {
        if isPlaying { player.pause() } else { player.playImmediately(atRate: rate) }
    }

    func skip(by delta: Double) { seek(to: currentTime + delta) }
}
