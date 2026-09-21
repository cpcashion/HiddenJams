//
//  SpotifyAPIService.swift
//  SpotifyHiddenGems
//
//  Service layer for all Spotify Web API calls
//

import Foundation
import Combine

class SpotifyAPIService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let baseURL = "https://api.spotify.com/v1"
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - User Profile
    
    func getCurrentUser(token: String) async throws -> SpotifyUser {
        let url = URL(string: "\(baseURL)/me")!
        return try await makeRequest(url: url, token: token)
    }
    
    // MARK: - Get ALL Liked Songs (Paginated)
    
    func getAllLikedTracks(token: String, progress: @escaping (Int, Int) -> Void) async throws -> [SpotifyTrack] {
        var allTracks: [SpotifyTrack] = []
        var offset = 0
        let limit = 50
        var total = 0
        
        repeat {
            let url = URL(string: "\(baseURL)/me/tracks?limit=\(limit)&offset=\(offset)")!
            let response: PagingObject<SavedTrack> = try await makeRequest(url: url, token: token)
            
            total = response.total
            // Filter out local tracks (nil spotifyId)
            let validTracks = response.items.map { $0.track }.filter { $0.spotifyId != nil }
            allTracks.append(contentsOf: validTracks)
            offset += limit
            
            // Report progress
            progress(allTracks.count, total)
            
            if response.next == nil {
                break
            }
            
            // Add delay to prevent rate limiting (reduced for speed, relies on 429 handler)
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        } while offset < total
        
        return allTracks
    }
    
    // MARK: - Get ALL Playlists and Tracks
    
    func getAllPlaylistTracks(token: String, progress: @escaping (Int, Int) -> Void) async throws -> [SpotifyTrack] {
        // First, get all playlists
        var allPlaylists: [SpotifyPlaylist] = []
        var offset = 0
        let limit = 50
        
        repeat {
            let url = URL(string: "\(baseURL)/me/playlists?limit=\(limit)&offset=\(offset)")!
            let response: PagingObject<SpotifyPlaylist> = try await makeRequest(url: url, token: token)
            
            allPlaylists.append(contentsOf: response.items)
            offset += limit
            
            if response.next == nil {
                break
            }
            
            // Add delay to prevent rate limiting (increased due to strict limits)
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2.0s
        } while true
        
        // Now get tracks from each playlist
        var allTracks: [SpotifyTrack] = []
        var processedPlaylists = 0
        
        for playlist in allPlaylists {
            var playlistOffset = 0
            
            repeat {
                let url = URL(string: "\(baseURL)/playlists/\(playlist.id)/tracks?limit=50&offset=\(playlistOffset)")!
                let response: PagingObject<PlaylistTrack> = try await makeRequest(url: url, token: token)
                
                let validTracks = response.items.compactMap { $0.track }.filter { $0.spotifyId != nil }
                allTracks.append(contentsOf: validTracks)
                playlistOffset += 50
                
                if response.next == nil {
                    break
                }
                
                // Add delay to prevent rate limiting (increased due to strict limits)
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2.0s
            } while true
            
            processedPlaylists += 1
            progress(processedPlaylists, allPlaylists.count)
        }
        
        // Remove duplicates
        let uniqueTracks = Array(Set(allTracks.map { $0.id }))
            .compactMap { id in allTracks.first(where: { $0.id == id }) }
        
        return uniqueTracks
    }
    
    // MARK: - Audio Features
    
    // Cache for audio features to avoid redundant API calls
    private var audioFeaturesCache: [String: AudioFeatures] = [:]
    
    func getAudioFeatures(trackIds: [String], token: String) async throws -> [AudioFeatures] {
        // IMPORTANT: Audio features are OPTIONAL - if API fails, return empty to not block discovery
        do {
            var features: [AudioFeatures] = []
            var uncachedIds: [String] = []
            
            // Check cache first
            for id in trackIds {
                if let cached = audioFeaturesCache[id] {
                    features.append(cached)
                } else {
                    uncachedIds.append(id)
                }
            }
            
            if uncachedIds.isEmpty {
                print("✅ All \(trackIds.count) audio features loaded from cache")
                return features
            }
            
            print("📊 Fetching audio features for \(uncachedIds.count) tracks (\(audioFeaturesCache.count) cached)...")
            
            // Spotify allows up to 100 IDs per request
            // We'll use 50 to be safe and consistent with other batch operations
            let batchSize = 50
            for batch in uncachedIds.chunked(into: batchSize) {
                let idsString = batch.joined(separator: ",")
                let url = URL(string: "\(baseURL)/audio-features?ids=\(idsString)")!
                
                // Use the batch response struct
                let response: AudioFeaturesResponse = try await makeRequest(url: url, token: token)
                
                for (index, feature) in response.audioFeatures.enumerated() {
                    if let feature = feature {
                        features.append(feature)
                        // Cache it
                        audioFeaturesCache[feature.id] = feature
                    } else {
                        print("⚠️ Audio features missing for track ID: \(batch[index])")
                    }
                }
                
                // Small delay between batches
                if batch != uncachedIds.chunked(into: batchSize).last {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }
            }
            
            print("✅ Retrieved \(features.count) audio features")
            return features
        } catch {
            print("⚠️ Failed to fetch audio features: \(error) - continuing without them")
            return []
        }
    }

    
    // MARK: - Search API (Discovery)
    
    func searchTracks(
        query: String,
        limit: Int = 50,
        offset: Int = 0,
        market: String? = nil,
        token: String
    ) async throws -> [SpotifyTrack] {
        var components = URLComponents(string: "\(baseURL)/search")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        if let market = market {
            queryItems.append(URLQueryItem(name: "market", value: market))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        
        print("🔍 Searching Spotify: \(query)")
        let response: SearchResponse = try await makeRequest(url: url, token: token)
        print("✅ Found \(response.tracks.items.count) tracks")
        return response.tracks.items
    }
    
    // MARK: - Recommendations API
    
    /// Get track recommendations based on seed genres
    /// This API supports genres like "drum-and-bass" that don't work in search
    func getRecommendations(
        seedGenres: [String],
        limit: Int = 50,
        market: String? = nil,
        token: String
    ) async throws -> [SpotifyTrack] {
        var components = URLComponents(string: "\(baseURL)/recommendations")!
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "seed_genres", value: seedGenres.joined(separator: ",")),
            URLQueryItem(name: "limit", value: "\(min(limit, 100))")  // Max 100
        ]
        
        if let market = market {
            queryItems.append(URLQueryItem(name: "market", value: market))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        
        print("🎵 Fetching recommendations for genres: \(seedGenres.joined(separator: ", "))")
        let response: RecommendationsResponse = try await makeRequest(url: url, token: token)
        print("✅ Got \(response.tracks.count) recommendations")
        return response.tracks
    }
    
    // MARK: - Cross-Reference Search Methods
    
    /// Search for an artist by name (for cross-referencing with external APIs)
    func searchArtist(name: String, token: String) async throws -> [SpotifyArtist] {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: name),
            URLQueryItem(name: "type", value: "artist"),
            URLQueryItem(name: "limit", value: "10")
        ]
        
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        
        let response: ArtistSearchResponse = try await makeRequest(url: url, token: token)
        return response.artists.items
    }
    
    /// Search for a track by name and artist (for cross-referencing with external APIs)
    func searchTrack(name: String, artist: String, token: String) async throws -> [SpotifyTrack] {
        let query = "track:\(name) artist:\(artist)"
        
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "10")
        ]
        
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        
        let response: SearchResponse = try await makeRequest(url: url, token: token)
        return response.tracks.items
    }
    
    /// Get artist's latest releases within specified months
    func getArtistLatestReleases(artistId: String, withinMonths months: Int, token: String) async throws -> [SpotifyAlbum] {
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let albums = try await getArtistAlbums(artistId: artistId, limit: 50, token: token)
        
        // Filter for recent releases
        return albums.filter { album in
            guard let releaseDateString = album.releaseDate else { return false }
            
            // Parse various date formats
            let formatters = [
                "yyyy-MM-dd",
                "yyyy-MM",
                "yyyy"
            ]
            
            for format in formatters {
                let formatter = DateFormatter()
                formatter.dateFormat = format
                if let releaseDate = formatter.date(from: releaseDateString) {
                    return releaseDate >= cutoffDate
                }
            }
            
            return false
        }
    }
    
    // MARK: - Artist Top Tracks
    
    func getArtistTopTracks(
        artistId: String,
        market: String = "US",
        token: String
    ) async throws -> [SpotifyTrack] {
        let url = URL(string: "\(baseURL)/artists/\(artistId)/top-tracks?market=\(market)")!
        let response: ArtistTopTracksResponse = try await makeRequest(url: url, token: token)
        return response.tracks
    }
    
    // MARK: - Recently Played
    
    /// Get the user's recently played tracks (up to 50)
    func getRecentlyPlayed(token: String, limit: Int = 50) async throws -> [PlayHistory] {
        let url = URL(string: "\(baseURL)/me/player/recently-played?limit=\(min(limit, 50))")!
        let response: RecentlyPlayedResponse = try await makeRequest(url: url, token: token)
        return response.items
    }
    
    // MARK: - Top Artists and Tracks
    
    /// Get user's top artists with customizable time range
    /// - Parameters:
    ///   - token: Spotify access token
    ///   - limit: Number of artists to fetch (max 50)
    ///   - timeRange: .shortTerm (4 weeks), .mediumTerm (6 months), .longTerm (all time)
    func getTopArtists(token: String, limit: Int = 50, timeRange: TimeRange = .longTerm) async throws -> [SpotifyArtist] {
        let url = URL(string: "\(baseURL)/me/top/artists?limit=\(min(limit, 50))&time_range=\(timeRange.rawValue)")!
        let response: TopItemsResponse<SpotifyArtist> = try await makeRequest(url: url, token: token)
        return response.items
    }
    
    /// Get user's top tracks with customizable time range
    /// - Parameters:
    ///   - token: Spotify access token
    ///   - limit: Number of tracks to fetch
    ///   - timeRange: .shortTerm (4 weeks), .mediumTerm (6 months), .longTerm (all time)
    func getTopTracks(token: String, limit: Int = 50, timeRange: TimeRange = .longTerm) async throws -> [SpotifyTrack] {
        // If limit is small, use single request
        if limit <= 50 {
            let url = URL(string: "\(baseURL)/me/top/tracks?limit=\(limit)&time_range=\(timeRange.rawValue)")!
            let response: TopItemsResponse<SpotifyTrack> = try await makeRequest(url: url, token: token)
            return response.items
        }
        
        // Pagination for larger limits
        var allTracks: [SpotifyTrack] = []
        var offset = 0
        let batchSize = 50
        
        while allTracks.count < limit {
            let remaining = limit - allTracks.count
            let currentLimit = min(remaining, batchSize)
            
            let url = URL(string: "\(baseURL)/me/top/tracks?limit=\(currentLimit)&offset=\(offset)&time_range=\(timeRange.rawValue)")!
            let response: TopItemsResponse<SpotifyTrack> = try await makeRequest(url: url, token: token)
            
            if response.items.isEmpty {
                break
            }
            
            allTracks.append(contentsOf: response.items)
            offset += currentLimit
            
            // Rate limiting protection
            if allTracks.count < limit {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay
            }
        }
        
        return allTracks
    }
    
    // MARK: - Related Artists
    
    func getRelatedArtists(artistId: String, token: String) async throws -> [SpotifyArtist] {
        let url = URL(string: "\(baseURL)/artists/\(artistId)/related-artists")!
        let response: RelatedArtistsResponse = try await makeRequest(url: url, token: token)
        return response.artists
    }
    
    // MARK: - Artist Details (with follower count)
    
    func getArtistDetails(artistId: String, token: String) async throws -> SpotifyArtist {
        let url = URL(string: "\(baseURL)/artists/\(artistId)")!
        return try await makeRequest(url: url, token: token)
    }
    
    func getArtists(ids: [String], token: String) async throws -> [SpotifyArtist] {
        guard !ids.isEmpty else { return [] }
        let idsString = ids.joined(separator: ",")
        let url = URL(string: "\(baseURL)/artists?ids=\(idsString)")!
        let response: ArtistsResponse = try await makeRequest(url: url, token: token)
        return response.artists
    }
    
    // MARK: - Artist Albums
    
    func getArtistAlbums(
        artistId: String,
        limit: Int = 50,
        offset: Int = 0,
        token: String
    ) async throws -> [SpotifyAlbum] {
        var components = URLComponents(string: "\(baseURL)/artists/\(artistId)/albums")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "include_groups", value: "album,single")  // Exclude compilations, appears_on
        ]
        
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        
        let response: ArtistAlbumsResponse = try await makeRequest(url: url, token: token)
        return response.items
    }
    
    // MARK: - Album Tracks
    
    func getAlbumTracks(albumId: String, token: String) async throws -> [SpotifyTrack] {
        let url = URL(string: "\(baseURL)/albums/\(albumId)/tracks")!
        let response: PagingObject<SpotifyTrack> = try await makeRequest(url: url, token: token)
        return response.items
    }
    
    // MARK: - New Releases
    
    func getNewReleases(
        limit: Int = 50,
        offset: Int = 0,
        token: String
    ) async throws -> [SpotifyAlbum] {
        var components = URLComponents(string: "\(baseURL)/browse/new-releases")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        
        let response: NewReleasesResponse = try await makeRequest(url: url, token: token)
        return response.albums.items
    }
    
    // MARK: - Playlist Management (NEW)
    
    func getUserPlaylists(token: String) async throws -> [SpotifyPlaylist] {
        var allPlaylists: [SpotifyPlaylist] = []
        var offset = 0
        let limit = 50
        
        repeat {
            let url = URL(string: "\(baseURL)/me/playlists?limit=\(limit)&offset=\(offset)")!
            let response: PagingObject<SpotifyPlaylist> = try await makeRequest(url: url, token: token)
            
            allPlaylists.append(contentsOf: response.items)
            offset += limit
            
            if response.next == nil {
                break
            }
        } while true
        
        return allPlaylists
    }
    
    func createPlaylist(userId: String, name: String, description: String, token: String) async throws -> SpotifyPlaylist {
        let url = URL(string: "\(baseURL)/users/\(userId)/playlists")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "name": name,
            "description": description,
            "public": false
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        return try JSONDecoder().decode(SpotifyPlaylist.self, from: data)
    }
    
    func addTracksToPlaylist(playlistId: String, uris: [String], token: String) async throws {
        let url = URL(string: "\(baseURL)/playlists/\(playlistId)/tracks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "uris": uris
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
    }
    
    // MARK: - Generic Request Handler
    
    private func makeRequest<T: Decodable>(url: URL, token: String, retryCount: Int = 0) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // Handle Rate Limiting (429)
        if httpResponse.statusCode == 429 {
            if retryCount < 3 {
                let retryAfter = Int(httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "1") ?? 1
                print("Rate limited. Waiting \(retryAfter) seconds...")
                try await Task.sleep(nanoseconds: UInt64(retryAfter + 1) * 1_000_000_000)
                return try await makeRequest(url: url, token: token, retryCount: retryCount + 1)
            } else {
                throw APIError.httpError(429)
            }
        }
        
        guard httpResponse.statusCode == 200 else {
            print("HTTP Error: \(httpResponse.statusCode) for URL: \(url.absoluteString)")
            if let responseBody = String(data: data, encoding: .utf8) {
                print("Response Body: \(responseBody)")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            print("Decoding error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Response JSON: \(jsonString)")
            }
            throw APIError.decodingError(error)
        }
    }
}

// MARK: - Supporting Types

private struct AudioFeaturesResponse: Codable {
    let audioFeatures: [AudioFeatures?]
    
    enum CodingKeys: String, CodingKey {
        case audioFeatures = "audio_features"
    }
}

enum APIError: Error {
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
