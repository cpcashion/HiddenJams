//
//  LastFmService.swift
//  HiddenJams
//
//  Service for querying Last.fm API for similar artists and tracks
//

import Foundation

class LastFmService {
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"
    private let apiKey = APIConfiguration.lastFmAPIKey
    
    // MARK: - Rate Limiting
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 0.2 // 5 requests/sec max
    
    private func requireAPIKey() throws {
        guard !apiKey.isEmpty else { throw LastFmError.missingApiKey }
    }

    private func throttle() async {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumRequestInterval {
                try? await Task.sleep(nanoseconds: UInt64((minimumRequestInterval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
    
    // MARK: - Similar Artists
    
    /// Get similar artists from Last.fm
    /// - Parameter artistName: Name of the artist to find similar artists for
    /// - Returns: Array of similar artist names with match scores
    func getSimilarArtists(artistName: String, limit: Int = 30) async throws -> [LastFmArtist] {
        try requireAPIKey()
        await throttle()
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "method", value: "artist.getsimilar"),
            URLQueryItem(name: "artist", value: artistName),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = components.url else {
            throw LastFmError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LastFmError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LastFmError.httpError(httpResponse.statusCode)
        }
        
        do {
            let result = try JSONDecoder().decode(LastFmSimilarArtistsResponse.self, from: data)
            print("✅ Last.fm: Found \(result.similarartists.artist.count) similar artists to '\(artistName)'")
            return result.similarartists.artist
        } catch {
            print("❌ Last.fm decoding error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Response: \(jsonString.prefix(500))")
            }
            throw LastFmError.decodingError(error)
        }
    }
    
    // MARK: - Similar Tracks
    
    /// Get similar tracks from Last.fm
    /// - Parameters:
    ///   - trackName: Name of the track
    ///   - artistName: Name of the artist
    /// - Returns: Array of similar tracks with match scores
    func getSimilarTracks(trackName: String, artistName: String, limit: Int = 30) async throws -> [LastFmTrack] {
        try requireAPIKey()
        await throttle()
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "method", value: "track.getsimilar"),
            URLQueryItem(name: "track", value: trackName),
            URLQueryItem(name: "artist", value: artistName),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        
        guard let url = components.url else {
            throw LastFmError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LastFmError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw LastFmError.httpError(httpResponse.statusCode)
        }
        
        do {
            let result = try JSONDecoder().decode(LastFmSimilarTracksResponse.self, from: data)
            print("✅ Last.fm: Found \(result.similartracks.track.count) similar tracks to '\(trackName)'")
            return result.similartracks.track
        } catch {
            print("❌ Last.fm decoding error: \(error)")
            throw LastFmError.decodingError(error)
        }
    }
}

// MARK: - Errors

enum LastFmError: Error {
    case missingApiKey
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case artistNotFound
    case trackNotFound
}
