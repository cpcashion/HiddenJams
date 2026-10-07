//
//  AudioPreviewManager.swift
//  HiddenJams
//
//  Manages 30-second audio preview playback.
//  Resilient queue playback: tracks with missing/unplayable preview URLs
//  are automatically skipped so playback never dead-stops mid-queue.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit

class AudioPreviewManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrackId: String?
    @Published var queue: [RecommendedTrack] = []
    @Published var currentIndex: Int = 0
    @Published var currentTrack: RecommendedTrack?
    @Published var hasPreview: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 30.0
    /// True while a full song (not the 30s preview) is playing in-app.
    @Published var isFullSongActive: Bool = false
    /// Which backend is playing the full song, if any.
    @Published var fullSongBackend: FullSongBackend?

    /// Provides the Spotify web-API token for the Premium check. Wired up
    /// by the app at launch.
    var spotifyTokenProvider: (() -> String?)?

    enum FullSongBackend {
        case appleMusic
        case spotify
    }

    enum FullSongAvailability {
        case appleMusic
        case spotify
        case unavailable(String)
    }

    private let appleMusicFullSong = AppleMusicFullSongService()
    private let spotifyFullSong = SpotifyFullSongService()
    private var cancellables = Set<AnyCancellable>()

    // Legacy support alias
    var playlist: [RecommendedTrack] { queue }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false

    /// Counts consecutive unplayable tracks; reset once a track actually
    /// becomes ready. Prevents infinite skip loops when every URL is dead.
    private var consecutiveFailures = 0

    init() {
        configureAudioSession()
        setupInterruptionHandling()
        setupRemoteCommands()
        setupFullSongRouting()
    }

    // MARK: - Full Song (in-app, not the 30s preview)

    /// Wires the full-song services' position/state into the player's
    /// published values while a full song is active, so the shelf,
    /// expanded player scrubber, and Now Playing all stay correct.
    private func setupFullSongRouting() {
        // The services are @MainActor; hop there for the subscription setup.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.appleMusicFullSong.$position
                .receive(on: RunLoop.main)
                .sink { [weak self] pos in
                    guard let self, self.fullSongBackend == .appleMusic else { return }
                    self.currentTime = pos
                }
                .store(in: &self.cancellables)
            self.appleMusicFullSong.$duration
                .receive(on: RunLoop.main)
                .sink { [weak self] dur in
                    guard let self, self.fullSongBackend == .appleMusic else { return }
                    self.duration = dur
                    if dur > 0 { self.updateNowPlaying() }
                }
                .store(in: &self.cancellables)
            self.appleMusicFullSong.$isPlaying
                .receive(on: RunLoop.main)
                .sink { [weak self] playing in
                    guard let self, self.fullSongBackend == .appleMusic else { return }
                    self.isPlaying = playing
                    self.refreshNowPlayingPlaybackState()
                }
                .store(in: &self.cancellables)

            self.spotifyFullSong.$position
                .receive(on: RunLoop.main)
                .sink { [weak self] pos in
                    guard let self, self.fullSongBackend == .spotify else { return }
                    self.currentTime = pos
                }
                .store(in: &self.cancellables)
            self.spotifyFullSong.$duration
                .receive(on: RunLoop.main)
                .sink { [weak self] dur in
                    guard let self, self.fullSongBackend == .spotify else { return }
                    self.duration = dur
                    if dur > 0 { self.updateNowPlaying() }
                }
                .store(in: &self.cancellables)
            self.spotifyFullSong.$isPlaying
                .receive(on: RunLoop.main)
                .sink { [weak self] playing in
                    guard let self, self.fullSongBackend == .spotify else { return }
                    self.isPlaying = playing
                    self.refreshNowPlayingPlaybackState()
                }
                .store(in: &self.cancellables)

            self.appleMusicFullSong.onEnded = { [weak self] in
                self?.fullSongDidEnd()
            }
            self.spotifyFullSong.onEnded = { [weak self] in
                self?.fullSongDidEnd()
            }
        }
    }

    /// Which in-app full-song option is available for the current track.
    /// Prefers Apple Music (no extra auth), then Spotify (Premium + app).
    func checkFullSongAvailability() async -> FullSongAvailability {
        guard let track = currentTrack else {
            return .unavailable("No track playing")
        }
        if await appleMusicFullSong.canPlayFullSongs(),
           await appleMusicFullSong.catalogID(for: track) != nil {
            return .appleMusic
        }
        if track.track.isSpotifyOrigin,
           spotifyFullSong.isSpotifyAppInstalled,
           await isSpotifyPremium() {
            return .spotify
        }
        if !spotifyFullSong.isSpotifyAppInstalled, track.track.isSpotifyOrigin {
            return .unavailable("Full song needs the Spotify app + Premium, or Apple Music")
        }
        return .unavailable("Full song needs Apple Music or Spotify Premium")
    }

    private func isSpotifyPremium() async -> Bool {
        guard let token = spotifyTokenProvider?(), !token.isEmpty else { return false }
        do {
            let user = try await SpotifyAPIService().getCurrentUser(token: token)
            return user.isPremium
        } catch {
            return false
        }
    }

    /// Swaps the 30s preview for the full song, in-app. The player UI
    /// doesn't change — the scrubber just spans the full duration.
    func playFullSong() async -> Bool {
        guard let track = currentTrack, !isFullSongActive else { return false }
        // Pause the preview first so there's no overlap.
        player?.pause()

        switch await checkFullSongAvailability() {
        case .appleMusic:
            guard let catalogID = await appleMusicFullSong.catalogID(for: track) else { return false }
            do {
                try await appleMusicFullSong.play(catalogID: catalogID)
            } catch {
                print("⚠️ Full song (Apple Music) failed: \(error)")
                player?.play() // fall back to the preview
                return false
            }
            fullSongBackend = .appleMusic
        case .spotify:
            let uri = track.spotifyURI.hasPrefix("spotify:track:")
                ? track.spotifyURI
                : "spotify:track:\(track.track.id)"
            guard await spotifyFullSong.play(uri: uri) else {
                player?.play()
                return false
            }
            fullSongBackend = .spotify
        case .unavailable(let reason):
            print("ℹ️ Full song unavailable: \(reason)")
            player?.play()
            return false
        }

        isFullSongActive = true
        updateNowPlaying()
        print("🎵 Full song playing in-app via \(fullSongBackend == .appleMusic ? "Apple Music" : "Spotify")")
        return true
    }

    /// Leaves full-song mode. Called on track end, next/previous, or
    /// when the user toggles back to the preview.
    func exitFullSong() {
        guard isFullSongActive else { return }
        let backend = fullSongBackend
        Task { @MainActor [weak self] in
            guard let self else { return }
            if backend == .appleMusic {
                self.appleMusicFullSong.stop()
            } else if backend == .spotify {
                self.spotifyFullSong.stop()
            }
        }
        isFullSongActive = false
        fullSongBackend = nil
    }

    private func fullSongDidEnd() {
        print("✅ Full song ended — back to previews")
        exitFullSong()
        playNext()
    }

    /// Routes Spotify SDK OAuth callbacks. Called from the app's onOpenURL.
    func handleSpotifyRedirect(url: URL) -> Bool {
        spotifyFullSong.handleRedirect(url: url)
    }

    // MARK: - Now Playing (Lock Screen / Apple Watch)

    /// Wires up the system transport controls (Control Center, lock screen,
    /// and Apple Watch Now Playing). When these are active, raising the
    /// wrist on a paired Apple Watch automatically shows playback controls
    /// for Hidden Jams — same as Spotify.
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrevious()
            return .success
        }
    }

    /// Pushes the current track into MPNowPlayingInfoCenter so iOS (and the
    /// paired Apple Watch) shows it in Now Playing.
    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.track.name,
            MPMediaItemPropertyArtist: track.track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.track.album.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Load album artwork in the background for the Now Playing UI.
        if let artURL = track.track.album.images.first?.url {
            URLSession.shared.dataTask(with: artURL) { [weak self] data, _, _ in
                guard let self, let data, let image = UIImage(data: data) else { return }
                // Only apply if this is still the current track.
                guard self.currentTrack?.id == track.id else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                DispatchQueue.main.async {
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updated[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                }
            }.resume()
        }
    }

    /// Refreshes elapsed time / play state in Now Playing (cheap — text only).
    private func refreshNowPlayingPlaybackState() {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo,
              !info.isEmpty else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func setupInterruptionHandling() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            self?.handleInterruption(note)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            pause()
            print("⏸️ Audio interrupted (call/notification)")
        case .ended:
            if let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt {
                let opts = AVAudioSession.InterruptionOptions(rawValue: optRaw)
                if opts.contains(.shouldResume) && wasPlayingBeforeInterruption {
                    print("▶️ Resuming after interruption")
                    resume()
                }
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    // MARK: - Queue Management

    func loadQueue(_ tracks: [RecommendedTrack], autoPlay: Bool = true) {
        queue = tracks
        currentIndex = 0
        consecutiveFailures = 0
        if autoPlay && !queue.isEmpty {
            playTrackAtIndex(0)
        }
    }

    /// Nearest index >= `index` whose track has a usable preview URL.
    /// Returns nil when nothing from `index` to the end of the queue is playable.
    private func nextPlayableIndex(from index: Int) -> Int? {
        var i = index
        while i < queue.count {
            let track = queue[i]
            if let urlString = track.track.previewUrl,
               !urlString.isEmpty,
               URL(string: urlString) != nil {
                return i
            }
            i += 1
        }
        return nil
    }

    func playTrackAtIndex(_ index: Int) {
        exitFullSong()
        guard !queue.isEmpty else { return }
        guard index < queue.count else {
            print("📭 No more tracks in playlist")
            stop()
            return
        }

        // Skip tracks with missing/unusable preview URLs instead of dead-stopping.
        guard let playableIndex = nextPlayableIndex(from: max(index, 0)) else {
            print("📭 No playable tracks remaining in queue")
            stop()
            return
        }
        if playableIndex != index {
            print("⏭️ Skipping track(s) with no preview URL")
        }

        let track = queue[playableIndex]
        currentIndex = playableIndex
        currentTrack = track
        hasPreview = true

        startPlayback(urlString: track.track.previewUrl!, trackId: track.id)
    }

    /// Starts playback of a preview URL, or skips forward on failure.
    private func startPlayback(urlString: String, trackId: String) {
        // Tapping the currently-loaded track just resumes (don't restart it)
        // — unless the item failed to load, in which case restart it.
        if currentTrackId == trackId, let item = player?.currentItem {
            if item.status != .failed {
                player?.play()
                isPlaying = true
                refreshNowPlayingPlaybackState()
                return
            }
            // Failed item: fall through and rebuild the player.
        }

        teardownPlayer()

        guard let previewURL = URL(string: urlString) else {
            print("⚠️ Malformed preview URL, skipping")
            skipAfterFailure()
            return
        }

        let playerItem = AVPlayerItem(url: previewURL)
        player = AVPlayer(playerItem: playerItem)
        currentTrackId = trackId

        // Time observer for progress UI
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }

        // Natural end of the 30s preview -> advance
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.handleTrackEnded()
        }

        // Playback error mid-stream (e.g. 403 on an expired Deezer URL) -> skip
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] note in
            if let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("⚠️ Preview failed mid-stream: \(err.localizedDescription)")
            }
            self?.skipAfterFailure()
        }

        // Item failed to load at all (404/expired signed URL) -> skip.
        // A loaded item resets the failure counter.
        statusObservation = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                self?.consecutiveFailures = 0
            case .failed:
                print("⚠️ Preview URL failed to load: \(item.error?.localizedDescription ?? "unknown error")")
                self?.skipAfterFailure()
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        player?.play()
        isPlaying = true
        updateNowPlaying()
        print("▶️ Playing: \(currentTrack?.track.name ?? "?") (\(currentIndex + 1)/\(queue.count))")
    }

    /// Advances past an unplayable track. Gives up gracefully if the whole
    /// queue is dead instead of looping forever.
    private func skipAfterFailure() {
        consecutiveFailures += 1
        if consecutiveFailures > queue.count {
            print("📭 Too many consecutive playback failures, stopping")
            consecutiveFailures = 0
            stop()
            return
        }
        // Hop to the next playable track after the one that just failed.
        playTrackAtIndex(currentIndex + 1)
    }

    private func handleTrackEnded() {
        print("✅ Track ended, auto-advancing...")
        consecutiveFailures = 0
        playNext()
    }

    func playNext() {
        exitFullSong()
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            playTrackAtIndex(nextIndex)
        } else {
            print("🎉 Playlist complete!")
            stop()
        }
    }

    func playPrevious() {
        exitFullSong()
        if currentTime > 3.0 {
            player?.seek(to: .zero)
            currentTime = 0.0
        } else {
            let prevIndex = currentIndex - 1
            if prevIndex >= 0 {
                playTrackAtIndex(prevIndex)
            }
        }
    }

    func playTrack(_ track: RecommendedTrack) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            playTrackAtIndex(index)
        } else {
            // Not in queue: replace queue with this single track
            loadQueue([track])
        }
    }

    /// Direct single-preview playback (used by track cards). Routes through
    /// the queue machinery so end-of-track advance and state stay consistent.
    func playPreview(url: String, trackId: String) {
        guard !url.isEmpty, URL(string: url) != nil else {
            print("⚠️ No playable preview URL for track \(trackId)")
            return
        }
        if let index = queue.firstIndex(where: { $0.id == trackId }) {
            playTrackAtIndex(index)
        } else {
            // Not part of the current queue: just resume if it's the
            // current track, otherwise start it standalone.
            startPlayback(urlString: url, trackId: trackId)
        }
    }

    /// Plays raw SpotifyTracks (e.g. saved gems on the profile) with full
    /// UI sync. Wraps them as RecommendedTracks and loads the whole list as
    /// the queue starting at the tapped index — so the shelf, expanded
    /// player, and Now Playing all show the right song, and Next advances
    /// through the list instead of dead-ending.
    func playSpotifyTracks(_ tracks: [SpotifyTrack], startingAt index: Int) {
        guard !tracks.isEmpty else { return }
        let wrapped = tracks.map { spotifyTrack in
            RecommendedTrack(
                id: spotifyTrack.id,
                spotifyURI: spotifyTrack.uri,
                track: spotifyTrack,
                matchScore: 0,
                obscurityScore: 0,
                recencyScore: 0,
                totalScore: 0,
                obscurityReason: "",
                matchExplanation: "",
                similarToTrack: nil,
                similarityReasons: []
            )
        }
        let safeIndex = min(max(index, 0), wrapped.count - 1)
        loadQueue(wrapped, autoPlay: false)
        playTrackAtIndex(safeIndex)
    }

    func pause() {
        if isFullSongActive {
            let backend = fullSongBackend
            Task { @MainActor [weak self] in
                guard let self else { return }
                if backend == .appleMusic {
                    self.appleMusicFullSong.pause()
                } else {
                    self.spotifyFullSong.pause()
                }
            }
            return
        }
        player?.pause()
        isPlaying = false
        refreshNowPlayingPlaybackState()
    }

    func resume() {
        if isFullSongActive {
            let backend = fullSongBackend
            Task { @MainActor [weak self] in
                guard let self else { return }
                if backend == .appleMusic {
                    await self.appleMusicFullSong.resume()
                } else {
                    self.spotifyFullSong.resume()
                }
            }
            return
        }
        if player == nil, currentTrack != nil {
            // Player was torn down (e.g. after queue end) - restart the track.
            playTrackAtIndex(currentIndex)
            return
        }
        player?.play()
        isPlaying = true
        refreshNowPlayingPlaybackState()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func seek(to time: Double) {
        if isFullSongActive {
            let backend = fullSongBackend
            Task { @MainActor [weak self] in
                guard let self else { return }
                if backend == .appleMusic {
                    self.appleMusicFullSong.seek(to: time)
                } else {
                    self.spotifyFullSong.seek(to: time)
                }
            }
            return
        }
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }

    /// Tears down the AVPlayer and all of its observers. Observers are
    /// removed BEFORE the player is released (removing after nil-ing the
    /// player silently leaks the time observer).
    private func teardownPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        if let observer = failObserver {
            NotificationCenter.default.removeObserver(observer)
            failObserver = nil
        }

        statusObservation?.invalidate()
        statusObservation = nil

        player?.pause()
        player = nil
        currentTime = 0.0
    }

    func stop() {
        exitFullSong()
        teardownPlayer()
        isPlaying = false
        currentTrackId = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // NOTE: currentTrack/currentIndex are intentionally kept so the
        // player UI still shows the last card instead of vanishing.
    }

    deinit {
        teardownPlayer()
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
