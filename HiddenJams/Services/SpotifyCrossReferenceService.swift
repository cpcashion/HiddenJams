//
//  SpotifyCrossReferenceService.swift
//  HiddenJams
//
//  Critical service that maps external API suggestions to playable Spotify tracks
//

import Foundation

class SpotifyCrossReferenceService {
    private let spotifyAPI: SpotifyAPIService
    
    // MARK: - Caching
    private var artistCache: [String: SpotifyArtist] = [:]
    private var trackCache: [String: SpotifyTrack] = [:]
    
    init(spotifyAPI: SpotifyAPIService) {
        self.spotifyAPI = spotifyAPI
    }
    
    // MARK: - Artist Cross-Reference
    
    /// Find a Spotify artist by name
    /// - Parameters:
    ///   - name: Artist name from external API
    ///   - token: Spotify access token
    /// - Returns: Spotify match with confidence score
    func findSpotifyArtist(name: String, token: String) async throws -> SpotifyMatch? {
        // Check cache first
        let cacheKey = name.lowercased()
        if let cachedArtist = artistCache[cacheKey] {
            return createArtistMatch(from: cachedArtist, searchName: name)
        }
        
        // Search Spotify
        let searchResults = try await spotifyAPI.searchArtist(name: name, token: token)
        
        guard !searchResults.isEmpty else {
            print("⚠️  No Spotify match found for artist: '\(name)'")
            return nil
        }
        
        // Find best match using fuzzy matching
        let bestMatch = searchResults.max { artist1, artist2 in
            let score1 = calculateMatchConfidence(searchName: name, spotifyName: artist1.name)
            let score2 = calculateMatchConfidence(searchName: name, spotifyName: artist2.name)
            return score1 < score2
        }
        
        guard let artist = bestMatch else { return nil }
        
        let confidence = calculateMatchConfidence(searchName: name, spotifyName: artist.name)
        
        // Require 70% confidence minimum
        guard confidence >= 0.7 else {
            print("⚠️  Low confidence match (\(Int(confidence * 100))%) for '\(name)' -> '\(artist.name)'")
            return nil
        }
        
        // Cache the result
        artistCache[cacheKey] = artist
        
        return createArtistMatch(from: artist, searchName: name, confidence: confidence)
    }
    
    // MARK: - Track Cross-Reference
    
    /// Find a Spotify track by name and artist
    /// - Parameters:
    ///   - trackName: Track name from external API
    ///   - artistName: Artist name from external API
    ///   - token: Spotify access token
    /// - Returns: Spotify match with confidence score
    func findSpotifyTrack(trackName: String, artistName: String, token: String) async throws -> SpotifyMatch? {
        // Check cache first
        let cacheKey = "\(trackName.lowercased())_\(artistName.lowercased())"
        if let cachedTrack = trackCache[cacheKey] {
            return createTrackMatch(from: cachedTrack, searchName: trackName)
        }
        
        // Search Spotify
        let searchResults = try await spotifyAPI.searchTrack(name: trackName, artist: artistName, token: token)
        
        guard !searchResults.isEmpty else {
            print("⚠️  No Spotify match found for track: '\(trackName)' by '\(artistName)'")
            return nil
        }
        
        // Find best match (track name + artist name)
        let bestMatch = searchResults.max { track1, track2 in
            let trackScore1 = calculateMatchConfidence(searchName: trackName, spotifyName: track1.name)
            let artistScore1 = calculateMatchConfidence(searchName: artistName, spotifyName: track1.artistNames)
            let combined1 = (trackScore1 + artistScore1) / 2.0
            
            let trackScore2 = calculateMatchConfidence(searchName: trackName, spotifyName: track2.name)
            let artistScore2 = calculateMatchConfidence(searchName: artistName, spotifyName: track2.artistNames)
            let combined2 = (trackScore2 + artistScore2) / 2.0
            
            return combined1 < combined2
        }
        
        guard let track = bestMatch else { return nil }
        
        let trackConfidence = calculateMatchConfidence(searchName: trackName, spotifyName: track.name)
        let artistConfidence = calculateMatchConfidence(searchName: artistName, spotifyName: track.artistNames)
        let combinedConfidence = (trackConfidence + artistConfidence) / 2.0
        
        // Require 70% confidence minimum
        guard combinedConfidence >= 0.7 else {
            print("⚠️  Low confidence match (\(Int(combinedConfidence * 100))%) for '\(trackName)' by '\(artistName)'")
            return nil
        }
        
        // Cache the result
        trackCache[cacheKey] = track
        
        return createTrackMatch(from: track, searchName: trackName, confidence: combinedConfidence)
    }
    
    // MARK: - Batch Cross-Reference
    
    /// Cross-reference multiple artists at once
    func findSpotifyArtists(names: [String], token: String) async throws -> [SpotifyMatch] {
        var matches: [SpotifyMatch] = []
        
        for name in names {
            if let match = try await findSpotifyArtist(name: name, token: token) {
                matches.append(match)
            }
            // Small delay to avoid overwhelming Spotify API
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        return matches
    }
    
    /// Cross-reference multiple tracks at once
    func findSpotifyTracks(tracks: [(name: String, artist: String)], token: String) async throws -> [SpotifyMatch] {
        var matches: [SpotifyMatch] = []
        
        for (trackName, artistName) in tracks {
            if let match = try await findSpotifyTrack(trackName: trackName, artistName: artistName, token: token) {
                matches.append(match)
            }
            // Small delay to avoid overwhelming Spotify API
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        }
        
        return matches
    }
    
    // MARK: - Helper Methods
    
    private func createArtistMatch(from artist: SpotifyArtist, searchName: String, confidence: Double? = nil) -> SpotifyMatch {
        let uri = "spotify:artist:\(artist.id)"
        let calculatedConfidence = confidence ?? calculateMatchConfidence(searchName: searchName, spotifyName: artist.name)
        
        return SpotifyMatch(
            spotifyURI: uri,
            spotifyID: artist.id,
            name: artist.name,
            popularity: artist.popularity ?? 0,
            matchConfidence: calculatedConfidence,
            artistFollowers: artist.followers?.total
        )
    }
    
    private func createTrackMatch(from track: SpotifyTrack, searchName: String, confidence: Double? = nil) -> SpotifyMatch {
        let calculatedConfidence = confidence ?? calculateMatchConfidence(searchName: searchName, spotifyName: track.name)
        
        return SpotifyMatch(
            spotifyURI: track.uri,
            spotifyID: track.id,
            name: track.name,
            popularity: track.popularity,
            matchConfidence: calculatedConfidence,
            artistFollowers: track.artists.first?.followers?.total
        )
    }
    
    /// Calculate fuzzy match confidence between search name and Spotify result
    private func calculateMatchConfidence(searchName: String, spotifyName: String) -> Double {
        let search = searchName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let spotify = spotifyName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Exact match
        if search == spotify {
            return 1.0
        }
        
        // One contains the other
        if spotify.contains(search) || search.contains(spotify) {
            return 0.9
        }
        
        // Levenshtein distance-based similarity
        let distance = levenshteinDistance(search, spotify)
        let maxLength = max(search.count, spotify.count)
        
        if maxLength == 0 { return 0.0 }
        
        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        return max(0.0, similarity)
    }
    
    /// Calculate Levenshtein distance for fuzzy string matching
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
        
        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                if s1Array[i - 1] == s2Array[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(
                        matrix[i - 1][j] + 1,      // deletion
                        matrix[i][j - 1] + 1,      // insertion
                        matrix[i - 1][j - 1] + 1   // substitution
                    )
                }
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        artistCache.removeAll()
        trackCache.removeAll()
        print("🗑️  Cleared cross-reference cache")
    }
}
