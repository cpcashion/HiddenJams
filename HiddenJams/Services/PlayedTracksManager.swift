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

/// A single track the user swiped away (skipped) inside Hidden Jams.
/// The negative signal to `PlayedTrack`'s positive one — what the user
/// rejected tells us as much as what they played.
struct SkippedTrack: Codable, Identifiable {
    let trackId: String
    let name: String
    let artistName: String
    let skippedAt: Date

    var id: String { "\(trackId)-\(skippedAt.timeIntervalSince1970)" }

    init(track: SpotifyTrack, skippedAt: Date = Date()) {
        self.trackId = track.id
        self.name = track.name
        self.artistName = track.artistNames
        self.skippedAt = skippedAt
    }

    init(recommendedTrack: RecommendedTrack, skippedAt: Date = Date()) {
        self.init(track: recommendedTrack.track, skippedAt: skippedAt)
    }
}

/// Persistent log of tracks played AND skipped inside Hidden Jams,
/// most-recent first. Plays are the positive signal, skips the negative —
/// together they're the ground truth for what the user actually did with
/// served tracks (distinct from Spotify's recently-played, which includes
/// outside plays, and from discovery history, which records served tracks).
class PlayedTracksManager: ObservableObject {
    static let shared = PlayedTracksManager()

    private let playedKey = "hiddenjams_played_tracks"
    private let skippedKey = "hiddenjams_skipped_tracks"
    private let maxEntries = 100

    @Published private(set) var playedTracks: [PlayedTrack] = []
    @Published private(set) var skippedTracks: [SkippedTrack] = []

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
        savePlayed()
    }

    /// Record a skip (swipe left). A track skipped then replayed is removed
    /// from the skip log — the play wins.
    func recordSkip(_ track: RecommendedTrack) {
        let spotifyId = track.track.id
        // If they later played it, it's not a skip anymore.
        if playedTracks.contains(where: { $0.trackId == spotifyId }) {
            skippedTracks.removeAll(where: { $0.trackId == spotifyId })
        } else {
            let entry = SkippedTrack(recommendedTrack: track)
            skippedTracks.insert(entry, at: 0)
            if skippedTracks.count > maxEntries {
                skippedTracks = Array(skippedTracks.prefix(maxEntries))
            }
        }
        saveSkipped()
    }

    /// The last N tracks played in the app, most-recent first.
    func recentPlays(limit: Int = 5) -> [PlayedTrack] {
        Array(playedTracks.prefix(limit))
    }

    /// The last N tracks skipped in the app, most-recent first.
    func recentSkips(limit: Int = 20) -> [SkippedTrack] {
        Array(skippedTracks.prefix(limit))
    }

    func clear() {
        playedTracks = []
        skippedTracks = []
        savePlayed()
        saveSkipped()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: playedKey),
           let decoded = try? JSONDecoder().decode([PlayedTrack].self, from: data) {
            playedTracks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: skippedKey),
           let decoded = try? JSONDecoder().decode([SkippedTrack].self, from: data) {
            skippedTracks = decoded
        }
    }

    private func savePlayed() {
        if let data = try? JSONEncoder().encode(playedTracks) {
            UserDefaults.standard.set(data, forKey: playedKey)
        }
    }

    private func saveSkipped() {
        if let data = try? JSONEncoder().encode(skippedTracks) {
            UserDefaults.standard.set(data, forKey: skippedKey)
        }
    }
}
