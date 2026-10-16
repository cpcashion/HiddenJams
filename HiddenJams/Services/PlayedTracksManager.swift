import Foundation
import Combine

/// A single track the user actually played inside Hidden Jams
/// (not just saw in a deck). This is the ground truth for "what did
/// the user play in the app" — distinct from Spotify's recently-played
/// (which includes plays from outside the app) and from the discovery
/// history (which records served tracks, not plays).
struct PlayedTrack: Codable, Identifiable {
    let trackId: String
    let name: String
    let artistName: String
    let albumName: String
    let artworkURL: String?
    let playedAt: Date

    var id: String { "\(trackId)-\(playedAt.timeIntervalSince1970)" }

    init(track: SpotifyTrack, playedAt: Date = Date()) {
        self.trackId = track.id
        self.name = track.name
        self.artistName = track.artistNames
        self.albumName = track.album.name
        self.artworkURL = track.album.images.first?.url.absoluteString
        self.playedAt = playedAt
    }
}

/// Persistent log of tracks played inside Hidden Jams, most-recent first.
/// Cap: 100 entries. Recorded at every playback entry point in
/// AudioPreviewManager.
class PlayedTracksManager: ObservableObject {
    static let shared = PlayedTracksManager()

    private let storageKey = "hiddenjams_played_tracks"
    private let maxEntries = 100

    @Published private(set) var playedTracks: [PlayedTrack] = []

    private init() {
        load()
    }

    /// Record a play. Consecutive replays of the same track refresh the
    /// timestamp instead of duplicating the entry.
    func recordPlay(_ track: SpotifyTrack) {
        let entry = PlayedTrack(track: track)
        if let first = playedTracks.first, first.trackId == entry.trackId {
            playedTracks[0] = entry
        } else {
            playedTracks.insert(entry, at: 0)
        }
        if playedTracks.count > maxEntries {
            playedTracks = Array(playedTracks.prefix(maxEntries))
        }
        save()
    }

    /// The last N tracks played in the app, most-recent first.
    func recentPlays(limit: Int = 5) -> [PlayedTrack] {
        Array(playedTracks.prefix(limit))
    }

    func clear() {
        playedTracks = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([PlayedTrack].self, from: data) else {
            return
        }
        playedTracks = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playedTracks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
