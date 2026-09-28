//
//  MusicSource.swift
//  HiddenJams
//
//  Source-agnostic music library model. The app can analyze a user's taste from
//  Spotify, Apple Music, or both at once. Everything downstream (profile
//  analysis, discovery, playback) works with LibraryTrack; source-specific
//  services convert into this shape at the boundary.
//

import Foundation

// MARK: - Music Source

enum MusicSource: String, Codable, CaseIterable, Hashable {
    case spotify
    case appleMusic

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }

    var systemIconName: String {
        switch self {
        case .spotify: return "music.note.list"
        case .appleMusic: return "apple.logo"
        }
    }
}

// MARK: - Library Track (source-agnostic)

/// A single track from the user's library, regardless of which service it came from.
struct LibraryTrack: Codable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let albumName: String
    let releaseDate: String?      // "yyyy-MM-dd" (or prefix thereof)
    let genreNames: [String]
    let durationMs: Int
    let artworkURL: URL?
    let source: MusicSource

    /// Normalized identity used for cross-source deduplication.
    var dedupeKey: String {
        let t = LibraryTrack.normalize(title)
        let a = LibraryTrack.normalize(artistName)
        return "\(t) \(a)"
    }

    static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " - remastered", with: "")
            .replacingOccurrences(of: " - remaster", with: "")
            .components(separatedBy: " (")[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Merge multiple libraries, removing duplicates across sources.
    /// When the same song exists in both Spotify and Apple Music, the Spotify
    /// copy wins because it carries a Spotify ID (enables richer discovery).
    static func mergeDeduped(_ libraries: [LibraryTrack]...) -> [LibraryTrack] {
        mergeDeduped(libraries.flatMap { $0 })
    }

    static func mergeDeduped(_ tracks: [LibraryTrack]) -> [LibraryTrack] {
        var seen = Set<String>()
        var merged: [LibraryTrack] = []
        // Spotify first so its richer metadata wins dedupe collisions
        let ordered = tracks.sorted {
            if $0.source == $1.source { return false }
            return $0.source == .spotify
        }
        for track in ordered {
            if seen.insert(track.dedupeKey).inserted {
                merged.append(track)
            }
        }
        return merged
    }
}

// MARK: - Spotify Conversion

extension LibraryTrack {
    /// Build a LibraryTrack from a Spotify track. Genre names come from the
    /// caller's artist-genre lookup (Spotify tracks don't carry genres).
    init(from spotifyTrack: SpotifyTrack, genres: [String] = []) {
        self.id = spotifyTrack.id
        self.title = spotifyTrack.name
        self.artistName = spotifyTrack.artists.first?.name ?? "Unknown Artist"
        self.albumName = spotifyTrack.album.name
        self.releaseDate = spotifyTrack.album.releaseDate
        self.genreNames = genres
        self.durationMs = spotifyTrack.durationMs
        self.artworkURL = spotifyTrack.album.albumArtURL
        self.source = .spotify
    }

    /// Convert back to the SpotifyTrack shape the discovery engine and views
    /// already understand. Used for Apple Music tracks so the entire
    /// downstream pipeline (filtering, scoring, playback) works unchanged.
    /// The track keeps its deterministic LibraryTrack id (namespaced, e.g.
    /// "applemusic:...") so `id` is stable across accesses; `isSpotifyOrigin`
    /// stays false so no Spotify API lookup is ever attempted for it.
    /// - Parameters:
    ///   - popularity: 0-100 pseudo-popularity (maps from Last.fm listeners for Apple Music candidates)
    ///   - previewURL: playable 30s preview URL (iTunes for Apple Music candidates)
    func toSpotifyTrack(popularity: Int = 0, previewURL: String? = nil) -> SpotifyTrack {
        let artist = SpotifyArtist(
            spotifyId: source == .spotify ? id : nil,
            name: artistName,
            genres: genreNames.isEmpty ? nil : genreNames,
            popularity: nil,
            images: nil,
            followers: nil
        )
        let images: [SpotifyImage] = artworkURL.map { [SpotifyImage(url: $0, height: nil, width: nil)] } ?? []
        let album = SpotifyAlbum(
            spotifyId: nil,
            name: albumName,
            images: images,
            releaseDate: releaseDate,
            tracks: nil,
            artists: nil
        )
        return SpotifyTrack(
            spotifyId: id,
            name: title,
            artists: [artist],
            album: album,
            popularity: popularity,
            previewUrl: previewURL,
            uri: "",
            durationMs: durationMs
        )
    }
}
