//
//  AppleMusicFullSongService.swift
//  HiddenJams
//
//  In-app full-song playback for Apple Music subscribers via MusicKit.
//  Resolves a RecommendedTrack to an Apple Music catalog song (direct ID
//  for iTunes-origin tracks, ISRC search for Spotify-origin tracks) and
//  plays it through ApplicationMusicPlayer — the user never leaves the app.
//

import Foundation
import MusicKit
import Combine

enum FullSongError: Error {
    case notEligible(String)
    case notFound
    case playbackFailed(Error)
}

@MainActor
class AppleMusicFullSongService: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false

    private var pollTimer: Timer?
    private var endMonitorTimer: Timer?
    var onEnded: (() -> Void)?

    /// True when the user authorized MusicKit AND can play catalog content
    /// (i.e. an active Apple Music subscription). Never prompts — checks
    /// the current status only. (Prompting happens via the app's Apple
    /// Music connect flow, not as a side effect of a play tap.)
    func canPlayFullSongs() async -> Bool {
        guard MusicAuthorization.currentStatus == .authorized else { return false }
        do {
            let subscription = try await MusicSubscription.current
            return subscription.canPlayCatalogContent
        } catch {
            return false
        }
    }

    /// Resolves a track to an Apple Music catalog song ID.
    func catalogID(for track: RecommendedTrack) async -> String? {
        // iTunes-origin tracks: spotifyId is "itunes:{trackId}", and the
        // iTunes Store track ID is the Apple Music catalog song ID.
        if let spotifyId = track.track.spotifyId,
           spotifyId.hasPrefix("itunes:") {
            let id = String(spotifyId.dropFirst("itunes:".count))
            return id.isEmpty ? nil : id
        }
        // Spotify-origin: match by ISRC (universal recording identifier).
        if let isrc = track.track.isrc, !isrc.isEmpty {
            return await songID(matchingISRC: isrc)
        }
        // Last resort: title + artist search.
        return await songID(matchingQuery: "\(track.track.name) \(track.track.artistNames)")
    }

    private func songID(matchingISRC isrc: String) async -> String? {
        var request = MusicCatalogSearchRequest(term: isrc, types: [Song.self])
        request.limit = 5
        guard let response = try? await request.response() else { return nil }
        if let exact = response.songs.first(where: { $0.isrc?.lowercased() == isrc.lowercased() }) {
            return exact.id.rawValue
        }
        return response.songs.first?.id.rawValue
    }

    private func songID(matchingQuery query: String) async -> String? {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 3
        guard let response = try? await request.response() else { return nil }
        return response.songs.first?.id.rawValue
    }

    /// Starts full-song playback. Throws FullSongError.notFound when the
    /// track isn't in the Apple Music catalog.
    func play(catalogID: String) async throws {
        let request = MusicCatalogResourceRequest<Song>(
            matching: \.id, equalTo: MusicItemID(catalogID)
        )
        let response = try await request.response()
        guard let song = response.items.first else { throw FullSongError.notFound }

        let player = ApplicationMusicPlayer.shared
        player.queue = ApplicationMusicPlayer.Queue(for: [song])
        duration = song.duration ?? 0
        position = 0
        do {
            try await player.play()
        } catch {
            throw FullSongError.playbackFailed(error)
        }
        isPlaying = true
        startPolling()
    }

    func pause() {
        ApplicationMusicPlayer.shared.pause()
        isPlaying = false
    }

    func resume() async {
        do {
            try await ApplicationMusicPlayer.shared.play()
            isPlaying = true
        } catch {
            print("⚠️ MusicKit resume failed: \(error)")
        }
    }

    func seek(to seconds: Double) {
        ApplicationMusicPlayer.shared.playbackTime = seconds
        position = seconds
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        endMonitorTimer?.invalidate()
        endMonitorTimer = nil
        ApplicationMusicPlayer.shared.stop()
        isPlaying = false
        position = 0
        duration = 0
    }

    /// MusicKit has no end-of-track callback; poll for natural end.
    private func startPolling() {
        pollTimer?.invalidate()
        endMonitorTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let player = ApplicationMusicPlayer.shared
                self.position = player.playbackTime
                self.isPlaying = player.state.playbackStatus == .playing
                // Natural end: position near duration and not playing
                if self.duration > 0,
                   player.state.playbackStatus != .playing,
                   player.playbackTime >= self.duration - 1.0 {
                    self.stop()
                    self.onEnded?()
                }
            }
        }
    }
}
