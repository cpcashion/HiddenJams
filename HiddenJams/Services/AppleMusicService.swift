//
//  AppleMusicService.swift
//  HiddenJams
//
//  Apple Music integration via MusicKit. Reads the user's on-device media
//  library (songs added to their Apple Music library, including subscription
//  tracks). No developer token or API key is required for library requests —
//  only the NSAppleMusicUsageDescription plist entry and user authorization.
//

import Foundation
import Combine
import MusicKit
import MediaPlayer

/// Apple Music integration via MusicKit. Plain class (like SpotifyAuthManager);
/// published state is updated on the main thread.
class AppleMusicService: ObservableObject {
    @Published private(set) var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published private(set) var isFetching = false

    private let connectedKey = "appleMusicConnected"

    /// Whether the user has explicitly connected Apple Music in the app.
    /// (MusicAuthorization can be granted without the user choosing Apple Music
    /// as a source, so we track the choice separately.)
    var isConnected: Bool {
        get { UserDefaults.standard.bool(forKey: connectedKey) }
        set { UserDefaults.standard.set(newValue, forKey: connectedKey) }
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    init() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    // MARK: - Authorization

    /// Requests Apple Music / media-library access. Returns true when authorized.
    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        let granted = status == .authorized
        await MainActor.run {
            self.authorizationStatus = status
            if granted {
                self.isConnected = true
            }
        }
        return granted
    }

    func refreshStatus() {
        DispatchQueue.main.async {
            self.authorizationStatus = MusicAuthorization.currentStatus
        }
    }

    func disconnect() {
        // Note: the system authorization itself can only be revoked by the user
        // in Settings > Privacy > Media & Apple Music. We just stop using it.
        isConnected = false
    }

    // MARK: - Library Fetch

    /// Fetches the user's Apple Music library songs as source-agnostic tracks.
    /// Sorted by most recently added first so the freshest taste data wins when
    /// we cap the fetch size.
    func fetchLibraryTracks(limit: Int = 1000) async throws -> [LibraryTrack] {
        guard isAuthorized else {
            throw AppleMusicError.notAuthorized
        }

        await MainActor.run { self.isFetching = true }
        defer {
            Task { @MainActor in self.isFetching = false }
        }

        var request = MusicLibraryRequest<Song>()
        request.sort(by: \.libraryAddedDate, ascending: false)
        request.limit = limit

        let response = try await request.response()
        let tracks = response.items.compactMap { LibraryTrack(from: $0) }
        print("🍏 Fetched \(tracks.count) Apple Music library tracks")
        return tracks
    }

    // MARK: - Hidden Gems Playlist

    /// The playlist swiped-right gems land in — the Apple Music mirror of the
    /// Spotify "Hidden Jams" playlist.
    static let hiddenGemsPlaylistName = "Hidden Gems"

    /// Adds a catalog track (by iTunes Store ID) to the user's "Hidden Gems"
    /// playlist, creating the playlist on first use. Uses the on-device media
    /// library (MediaPlayer) — no developer token or web API needed.
    func saveTrackToHiddenGemsPlaylist(storeID: Int) async throws {
        guard isAuthorized else { throw AppleMusicError.notAuthorized }
        if MPMediaLibrary.authorizationStatus() != .authorized {
            let status = await withCheckedContinuation { cont in
                MPMediaLibrary.requestAuthorization { s in cont.resume(returning: s) }
            }
            guard status == .authorized else { throw AppleMusicError.notAuthorized }
        }
        let playlist = try await hiddenGemsPlaylist()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            playlist.addItem(withProductID: String(storeID)) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
        print("🍏 Added store ID \(storeID) to Apple Music '\(Self.hiddenGemsPlaylistName)' playlist")
    }

    /// Finds the existing "Hidden Gems" playlist or creates it.
    private func hiddenGemsPlaylist() async throws -> MPMediaPlaylist {
        if let existing = MPMediaQuery.playlists().collections?
            .compactMap({ $0 as? MPMediaPlaylist })
            .first(where: {
                ($0.value(forProperty: MPMediaPlaylistPropertyName) as? String)
                    == Self.hiddenGemsPlaylistName
            }) {
            return existing
        }
        let metadata = MPMediaPlaylistCreationMetadata(name: Self.hiddenGemsPlaylistName)
        return try await withCheckedThrowingContinuation { cont in
            MPMediaLibrary.default().getPlaylist(with: UUID(), creationMetadata: metadata) { playlist, error in
                if let playlist {
                    cont.resume(returning: playlist)
                } else {
                    cont.resume(throwing: error ?? AppleMusicError.fetchFailed(
                        "Couldn't create the Hidden Gems playlist in your library."
                    ))
                }
            }
        }
    }
}

enum AppleMusicError: LocalizedError {
    case notAuthorized
    case fetchFailed(String)
    /// Apple's catalog is reachable but no artist's popularity could be
    /// verified (the popularity lookup is temporarily unavailable). Served
    /// instead of mislabeling unverified mainstream tracks as hidden gems.
    case popularityUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access is not authorized. Connect Apple Music to analyze your library."
        case .fetchFailed(let message):
            return "Couldn't read your Apple Music library: \(message)"
        case .popularityUnavailable:
            return "We couldn't check what's underground right now — the popularity lookup is temporarily unavailable. Try again in a bit."
        }
    }
}

// MARK: - MusicKit Song → LibraryTrack

extension LibraryTrack {
    init?(from song: Song) {
        // Skip unplayable/placeholder entries
        guard !song.title.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        self.id = "applemusic:\(song.id.rawValue)"
        self.title = song.title
        self.artistName = song.artistName.isEmpty ? "Unknown Artist" : song.artistName
        self.albumName = song.albumTitle ?? "Unknown Album"
        self.releaseDate = song.releaseDate.map { dateFormatter.string(from: $0) }
        self.genreNames = song.genreNames ?? []
        self.durationMs = Int((song.duration ?? 0) * 1000)
        self.artworkURL = song.artwork?.url(width: 300, height: 300)
        self.source = .appleMusic
    }
}
