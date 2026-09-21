//
//  ExternalAPIModels.swift
//  HiddenJams
//
//  Data models for Last.fm, MusicBrainz, and cross-reference results
//

import Foundation

// MARK: - Last.fm Models

struct LastFmSimilarArtistsResponse: Codable {
    let similarartists: SimilarArtists
    
    struct SimilarArtists: Codable {
        let artist: [LastFmArtist]
    }
}

struct LastFmArtist: Codable {
    let name: String
    let match: String  // Similarity score as string (e.g. "0.82")
    let url: String?
    let image: [LastFmImage]?
    
    var matchScore: Double {
        Double(match) ?? 0.0
    }
}

struct LastFmSimilarTracksResponse: Codable {
    let similartracks: SimilarTracks
    
    struct SimilarTracks: Codable {
        let track: [LastFmTrack]
    }
}

struct LastFmTrack: Codable {
    let name: String
    let artist: LastFmTrackArtist
    let match: String
    let url: String?
    
    var matchScore: Double {
        Double(match) ?? 0.0
    }
    
    struct LastFmTrackArtist: Codable {
        let name: String
    }
}

struct LastFmImage: Codable {
    let text: String
    let size: String
    
    enum CodingKeys: String, CodingKey {
        case text = "#text"
        case size
    }
}

// MARK: - MusicBrainz Models

struct MBReleaseSearchResponse: Codable {
    let releases: [MBRelease]?
    let count: Int?
    
    enum CodingKeys: String, CodingKey {
        case releases
        case count = "release-count"
    }
}

struct MBRelease: Codable {
    let id: String
    let title: String
    let date: String?
    let status: String?
    let primaryType: String?
    let secondaryTypes: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case date
        case status
        case primaryType = "primary-type"
        case secondaryTypes = "secondary-types"
    }
    
    var isCompilation: Bool {
        if let primaryType = primaryType?.lowercased() {
            return primaryType == "compilation"
        }
        if let secondaryTypes = secondaryTypes {
            return secondaryTypes.contains { $0.lowercased() == "compilation" }
        }
        return false
    }
    
    var isRemaster: Bool {
        title.lowercased().contains("remaster") || 
        title.lowercased().contains("re-master")
    }
    
    var releaseDate: Date? {
        guard let date = date else { return nil }
        
        let formatters = [
            "yyyy-MM-dd",
            "yyyy-MM",
            "yyyy"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let parsedDate = formatter.date(from: date) {
                return parsedDate
            }
        }
        return nil
    }
}

// MARK: - Every Noise at Once Models

struct EveryNoiseGenre: Codable {
    let name: String
    let relatedGenres: [String]
    let artists: [String]
}

// MARK: - Cross-Reference Models

struct CrossReferenceResult {
    let externalName: String
    let externalSource: ExternalSource
    let spotifyMatch: SpotifyMatch?
    
    enum ExternalSource {
        case lastFm
        case musicBrainz
        case everyNoise
    }
}

struct SpotifyMatch {
    let spotifyURI: String
    let spotifyID: String
    let name: String
    let popularity: Int
    let matchConfidence: Double  // 0.0 to 1.0
    let artistFollowers: Int?
    
    var isObscure: Bool {
        popularity < 30 && (artistFollowers ?? Int.max) < 10000
    }
}

// MARK: - Recommended Track (Final Output)

struct RecommendedTrack: Identifiable, Equatable {
    static func == (lhs: RecommendedTrack, rhs: RecommendedTrack) -> Bool {
        lhs.id == rhs.id
    }
    let id: String
    let spotifyURI: String
    let track: SpotifyTrack
    let matchScore: Double
    let obscurityScore: Double
    let recencyScore: Double
    let totalScore: Double
    let obscurityReason: String
    
    // AI Explanation fields
    let matchExplanation: String  // "Similar to Gold Dust - same BPM..."
    let similarToTrack: SpotifyTrack?  // Reference track from user's library
    let similarityReasons: [String]  // ["Same genre", "Similar BPM: 174"]
    
    var displayScore: Int {
        Int(totalScore * 100)
    }
    
    // Convert to HiddenGem for backward compatibility with existing views
    func toHiddenGem() -> HiddenGem {
        HiddenGem(
            id: id,
            track: track,
            matchScore: totalScore * 100, // Convert 0-1 to 0-100
            matchReasons: similarityReasons.isEmpty ? [obscurityReason] : similarityReasons,
            streamCount: nil,
            popularity: track.popularity
        )
    }
}
