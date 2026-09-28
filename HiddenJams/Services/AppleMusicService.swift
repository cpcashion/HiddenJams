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
}

enum AppleMusicError: LocalizedError {
    case notAuthorized
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Apple Music access is not authorized. Connect Apple Music to analyze your library."
        case .fetchFailed(let message):
            return "Couldn't read your Apple Music library: \(message)"
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
