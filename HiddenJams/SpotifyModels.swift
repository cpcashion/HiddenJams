//
//  SpotifyModels.swift
//  SpotifyHiddenGems
//
//  Data models for Spotify API responses
//

import Foundation

// MARK: - User Profile
struct SpotifyUser: Codable {
    let id: String
    let displayName: String?
    let email: String?
    let images: [SpotifyImage]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case email
        case images
    }
}

// MARK: - Track
struct SpotifyTrack: Codable, Identifiable {
    let spotifyId: String?
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let popularity: Int
    let previewUrl: String?
    let uri: String
    let durationMs: Int
    
    var id: String { spotifyId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case spotifyId = "id"
        case name, artists, album, popularity, uri
        case previewUrl = "preview_url"
        case durationMs = "duration_ms"
    }
    
    var artistNames: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
}

// MARK: - Artist
struct SpotifyArtist: Codable, Identifiable {
    let spotifyId: String?
    let name: String
    let genres: [String]?
    let popularity: Int?
    let images: [SpotifyImage]?
    let followers: SpotifyFollowers?
    
    var id: String { spotifyId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case spotifyId = "id"
        case name, genres, popularity, images, followers
    }
}

// MARK: - Followers
struct SpotifyFollowers: Codable {
    let total: Int
}

// MARK: - Album
struct SpotifyAlbum: Codable, Identifiable {
    let spotifyId: String?
    let name: String
    let images: [SpotifyImage]
    let releaseDate: String?
    let tracks: AlbumTracksInfo?
    let artists: [SpotifyArtist]?
    
    var id: String { spotifyId ?? UUID().uuidString }
    
    enum CodingKeys: String, CodingKey {
        case spotifyId = "id"
        case name, images, tracks, artists
        case releaseDate = "release_date"
    }
    
    var albumArtURL: URL? {
        images.first?.url
    }
    
    struct AlbumTracksInfo: Codable {
        let items: [SpotifyTrack]?
        let total: Int?
    }
}

// MARK: - Image
struct SpotifyImage: Codable {
    let url: URL
    let height: Int?
    let width: Int?
}

// MARK: - Audio Features
struct AudioFeatures: Codable, Identifiable {
    let id: String
    let acousticness: Double
    let danceability: Double
    let energy: Double
    let instrumentalness: Double
    let key: Int
    let liveness: Double
    let loudness: Double
    let mode: Int
    let speechiness: Double
    let tempo: Double
    let timeSignature: Int
    let valence: Double
    
    enum CodingKeys: String, CodingKey {
        case id, acousticness, danceability, energy, instrumentalness
        case key, liveness, loudness, mode, speechiness, tempo, valence
        case timeSignature = "time_signature"
    }
}

// MARK: - Playlist
struct SpotifyPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]?
    let tracks: PlaylistTracksInfo
    let owner: PlaylistOwner
    
    struct PlaylistTracksInfo: Codable {
        let total: Int
    }
    
    struct PlaylistOwner: Codable {
        let id: String
        let displayName: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
        }
    }
}

// MARK: - API Response Wrappers
struct PagingObject<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let limit: Int
    let offset: Int
    let next: String?
    let previous: String?
}

struct SavedTrack: Codable {
    let track: SpotifyTrack
    let addedAt: String
    
    enum CodingKeys: String, CodingKey {
        case track
        case addedAt = "added_at"
    }
}

struct PlaylistTrack: Codable {
    let track: SpotifyTrack?
    let addedAt: String
    
    enum CodingKeys: String, CodingKey {
        case track
        case addedAt = "added_at"
    }
}

struct RecommendationsResponse: Codable {
    let seeds: [RecommendationSeed]
    let tracks: [SpotifyTrack]
}

struct RecommendationSeed: Codable {
    let initialPoolSize: Int
    let afterFilteringSize: Int
    let afterRelinkingSize: Int
    let id: String?
    let type: String
    
    enum CodingKeys: String, CodingKey {
        case initialPoolSize = "initialPoolSize"
        case afterFilteringSize = "afterFilteringSize"
        case afterRelinkingSize = "afterRelinkingSize"
        case id, type
    }
}

// MARK: - Top Items Response
struct TopItemsResponse<T: Codable>: Codable {
    let items: [T]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Search Response
struct SearchResponse: Codable {
    let tracks: TracksSearchResult
}

struct TracksSearchResult: Codable {
    let items: [SpotifyTrack]
    let total: Int
    let limit: Int
    let offset: Int
}

struct ArtistSearchResponse: Codable {
    let artists: ArtistsSearchResult
}

struct ArtistsSearchResult: Codable {
    let items: [SpotifyArtist]
    let total: Int
    let limit: Int
    let offset: Int
}


// MARK: - Artist Top Tracks Response
struct ArtistTopTracksResponse: Codable {
    let tracks: [SpotifyTrack]
}

// MARK: - Related Artists Response
struct RelatedArtistsResponse: Codable {
    let artists: [SpotifyArtist]
}

// MARK: - Artist Albums Response
struct ArtistAlbumsResponse: Codable {
    let items: [SpotifyAlbum]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - New Releases Response
struct NewReleasesResponse: Codable {
    let albums: AlbumsContainer
    
    struct AlbumsContainer: Codable {
        let items: [SpotifyAlbum]
        let total: Int
        let limit: Int
        let offset: Int
    }
}

// MARK: - Artists Response (Batch)
struct ArtistsResponse: Codable {
    let artists: [SpotifyArtist]
}

// MARK: - Audio Analysis Response (New)
struct AudioAnalysisResponse: Codable {
    let track: AudioAnalysisTrack
    let sections: [AudioSection]
    let beats: [AudioBeat]
}

struct AudioAnalysisTrack: Codable {
    let tempo: Double
    let key: Int
    let mode: Int
    let timeSignature: Int
    let loudness: Double
    
    enum CodingKeys: String, CodingKey {
        case tempo, key, mode, loudness
        case timeSignature = "time_signature"
    }
}

struct AudioSection: Codable {
    let loudness: Double
    let tempo: Double
    let timbre: [Double]
}

struct AudioBeat: Codable {
    let start: Double
    let confidence: Double
}

// MARK: - Recently Played Response
struct RecentlyPlayedResponse: Codable {
    let items: [PlayHistory]
    let cursors: PlaybackCursors?
}

struct PlayHistory: Codable, Identifiable {
    let track: SpotifyTrack
    let playedAt: String
    let context: PlayContext?
    
    var id: String { track.id + playedAt }
    
    enum CodingKeys: String, CodingKey {
        case track
        case playedAt = "played_at"
        case context
    }
    
    var playedAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: playedAt)
    }
}

struct PlayContext: Codable {
    let type: String?
    let uri: String?
}

struct PlaybackCursors: Codable {
    let after: String?
    let before: String?
}

// MARK: - Time Range for Top Items
enum TimeRange: String, CaseIterable {
    case shortTerm = "short_term"   // Last 4 weeks
    case mediumTerm = "medium_term" // Last 6 months
    case longTerm = "long_term"     // All time
    
    var displayName: String {
        switch self {
        case .shortTerm: return "This Month"
        case .mediumTerm: return "Last 6 Months"
        case .longTerm: return "All Time"
        }
    }
}

// MARK: - Double Extension for Clamping
extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}
