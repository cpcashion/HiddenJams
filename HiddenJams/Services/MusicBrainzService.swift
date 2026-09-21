//
//  MusicBrainzService.swift
//  HiddenJams
//
//  Service for verifying release dates and filtering compilations via MusicBrainz
//

import Foundation

class MusicBrainzService {
    private let baseURL = "https://musicbrainz.org/ws/2/"
    
    // MARK: - Rate Limiting (1 req/sec per MusicBrainz guidelines)
    private var lastRequestTime: Date?
    private let minimumRequestInterval: TimeInterval = 1.0
    
    private func throttle() async {
        if let lastTime = lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumRequestInterval {
                try? await Task.sleep(nanoseconds: UInt64((minimumRequestInterval - elapsed) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }
    
    // MARK: - Release Verification
    
    /// Verify the original release date and check if it's a compilation/remaster
    /// - Parameters:
    ///   - trackName: Name of the track
    ///   - artistName: Name of the artist
    /// - Returns: Release information including date and type
    func verifyRelease(trackName: String, artistName: String) async throws -> MBRelease? {
        await throttle()
        
        // Search for releases matching the track and artist
        var components = URLComponents(string: "\(baseURL)release/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "recording:\"\(trackName)\" AND artist:\"\(artistName)\""),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")
        ]
        
        guard let url = components.url else {
            throw MusicBrainzError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("HiddenJams/1.0 (contact@example.com)", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MusicBrainzError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 503 {
                // Rate limited, back off
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                throw MusicBrainzError.rateLimited
            }
            throw MusicBrainzError.httpError(httpResponse.statusCode)
        }
        
        do {
            let result = try JSONDecoder().decode(MBReleaseSearchResponse.self, from: data)
            
            // Filter out compilations and remasters, return the earliest original release
            let validReleases = result.releases?
                .filter { !$0.isCompilation && !$0.isRemaster }
                .sorted { ($0.releaseDate ?? Date.distantFuture) < ($1.releaseDate ?? Date.distantFuture) }
            
            if let earliestRelease = validReleases?.first {
                print("✅ MusicBrainz: '\(trackName)' originally released on \(earliestRelease.date ?? "unknown")")
                return earliestRelease
            }
            
            return nil
        } catch {
            print("❌ MusicBrainz decoding error: \(error)")
            throw MusicBrainzError.decodingError(error)
        }
    }
    
    /// Check if a track was released within the specified number of months
    /// - Parameters:
    ///   - trackName: Name of the track
    ///   - artistName: Name of the artist
    ///   - months: Number of months back to check
    /// - Returns: True if released within the timeframe, false otherwise
    func isRecentRelease(trackName: String, artistName: String, withinMonths months: Int) async throws -> Bool {
        guard let release = try await verifyRelease(trackName: trackName, artistName: artistName),
              let releaseDate = release.releaseDate else {
            return false
        }
        
        let cutoffDate = Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
        return releaseDate >= cutoffDate
    }
    
    /// Validate that a track is a genuine new release (not a compilation or remaster)
    /// - Parameters:
    ///   - trackName: Name of the track
    ///   - artistName: Name of the artist
    /// - Returns: Validation result with details
    func validateGenuineRelease(trackName: String, artistName: String) async throws -> ReleaseValidation {
        guard let release = try await verifyRelease(trackName: trackName, artistName: artistName) else {
            return ReleaseValidation(isValid: false, reason: "Release not found in MusicBrainz")
        }
        
        if release.isCompilation {
            return ReleaseValidation(isValid: false, reason: "Compilation album")
        }
        
        if release.isRemaster {
            return ReleaseValidation(isValid: false, reason: "Remaster or re-release")
        }
        
        return ReleaseValidation(
            isValid: true,
            reason: "Original release",
            releaseDate: release.releaseDate
        )
    }
}

// MARK: - Supporting Types

struct ReleaseValidation {
    let isValid: Bool
    let reason: String
    let releaseDate: Date?
    
    init(isValid: Bool, reason: String, releaseDate: Date? = nil) {
        self.isValid = isValid
        self.reason = reason
        self.releaseDate = releaseDate
    }
}

// MARK: - Errors

enum MusicBrainzError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case rateLimited
    case releaseNotFound
}
