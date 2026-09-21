//
//  HiddenGemsDiscovery.swift
//  SpotifyHiddenGems
//
//  Discovery engine for finding hidden gems using low-follower artist strategy
//  Revised Nov 2024 to focus on artist follower counts + recency
//

import Foundation
import Combine

class HiddenGemsDiscovery: ObservableObject {
    @Published var discoveredGems: [HiddenGem] = []
    @Published var isDiscovering = false
    @Published var errorMessage: String?
    
    private let apiService = SpotifyAPIService()
    private var knownTrackIds: Set<String> = []
    
    // Configurable thresholds
    private let followerThreshold = 10_000  // Max followers for "obscure" artist
    private let recencyDays = 60            // Only albums released in last 60 days
    private let maxArtistsToProcess = 50    // Top N artists from user profile
    private let relatedArtistsPerArtist = 10 // How many related artists to fetch per user artist
    
    // MARK: - Main Discovery Function
    
    func discoverHiddenGems(
        profile: ListeningProfile,
        userTracks: [String],
        token: String,
        count: Int = 50
    ) async {
        await MainActor.run {
            isDiscovering = true
            discoveredGems = []
            knownTrackIds = Set(userTracks)
        }
        
        do {
            print("🎯 Starting Low-Follower Artist Discovery")
            print("📊 Parameters: <\(followerThreshold) followers, last \(recencyDays) days")
            
            // Step 1: Extract unique artists from user's profile
            let userArtistIds = Set(profile.topArtists.prefix(maxArtistsToProcess).map { $0.id })
            print("👥 Processing \(userArtistIds.count) user artists")
            
            // Step 2: Get related artists for each user artist (parallel)
            let relatedArtists = try await fetchRelatedArtists(
                userArtistIds: Array(userArtistIds),
                token: token
            )
            print("🔗 Found \(relatedArtists.count) related artists")
            
            // Step 3: Fetch full artist details to get follower counts
            let artistsWithFollowers = try await fetchArtistDetails(
                artistIds: relatedArtists.map { $0.id },
                token: token
            )
            print("👤 Fetched details for \(artistsWithFollowers.count) artists")
            
            // Step 4: Filter to low-follower artists
            let lowFollowerArtists = artistsWithFollowers.filter { artist in
                guard let followers = artist.followers?.total else { return false }
                return followers < followerThreshold && !isMainstreamArtist(artist.name.lowercased())
            }
            print("⭐ Filtered to \(lowFollowerArtists.count) low-follower artists")
            
            // Step 5: Get recent albums from these artists
            let recentAlbums = try await fetchRecentAlbums(
                artists: lowFollowerArtists,
                token: token
            )
            print("💿 Found \(recentAlbums.count) recent albums")
            
            // Step 6: Extract tracks from recent albums
            var albumTracks = try await extractTracksFromAlbums(
                albums: recentAlbums,
                token: token
            )
            print("🎵 Extracted \(albumTracks.count) tracks from recent albums")
            
            // Step 7: Apply additional filters
            albumTracks = albumTracks.filter { track in
                !knownTrackIds.contains(track.id) &&
                track.popularity < 20 &&  // Extra safety filter
                !isCompilationAlbum(track.album.name)
            }
            print("✅ Filtered to \(albumTracks.count) candidate tracks")
            
            // Step 8: Score and rank
            let scoredGems = scoreTracks(albumTracks, lowFollowerArtists: lowFollowerArtists, against: profile)
            let topGems = Array(scoredGems.prefix(count))
            
            print("🎉 Discovery complete: Returning \(topGems.count) hidden gems")
            
            await MainActor.run {
                self.discoveredGems = topGems
                self.isDiscovering = false
            }
            
        } catch {
            print("❌ Discovery error: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isDiscovering = false
            }
        }
    }
    
    // MARK: - Step 2: Fetch Related Artists
    
    private func fetchRelatedArtists(userArtistIds: [String], token: String) async throws -> [SpotifyArtist] {
        var allRelatedArtists: [SpotifyArtist] = []
        var artistIdsSeen = Set<String>(userArtistIds) // Don't include user's own artists
        
        // Create tasks for parallel execution
        let tasks = userArtistIds.map { artistId in
            Task {
                try await apiService.getRelatedArtists(artistId: artistId, token: token)
            }
        }
        
        // Execute with rate limiting
        for (index, task) in tasks.enumerated() {
            do {
                let relatedArtists = try await task.value
                
                // Take top N related artists, deduplicate
                for artist in relatedArtists.prefix(relatedArtistsPerArtist) {
                    if !artistIdsSeen.contains(artist.id) {
                        allRelatedArtists.append(artist)
                        artistIdsSeen.insert(artist.id)
                    }
                }
                
                // Rate limiting: Small delay every 10 requests
                if (index + 1) % 10 == 0 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            } catch {
                print("⚠️ Failed to fetch related artists: \(error.localizedDescription)")
                continue
            }
        }
        
        return allRelatedArtists
    }
    
    // MARK: - Step 3: Fetch Full Artist Details
    
    private func fetchArtistDetails(artistIds: [String], token: String) async throws -> [SpotifyArtist] {
        var artistsWithDetails: [SpotifyArtist] = []
        
        // Batch fetch artist details
        for (index, artistId) in artistIds.enumerated() {
            do {
                let artist = try await apiService.getArtistDetails(artistId: artistId, token: token)
                artistsWithDetails.append(artist)
                
                // Rate limiting: Small delay every 20 requests
                if (index + 1) % 20 == 0 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            } catch {
                print("⚠️ Failed to fetch details for artist \(artistId): \(error.localizedDescription)")
                continue
            }
        }
        
        return artistsWithDetails
    }
    
    // MARK: - Step 5: Fetch Recent Albums
    
    private func fetchRecentAlbums(artists: [SpotifyArtist], token: String) async throws -> [SpotifyAlbum] {
        var recentAlbums: [SpotifyAlbum] = []
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -recencyDays, to: Date())!
        
        for (index, artist) in artists.enumerated() {
            do {
                let albums = try await apiService.getArtistAlbums(
                    artistId: artist.id,
                    limit: 20, // Get recent albums only
                    offset: 0,
                    token: token
                )
                
                // Filter to truly recent albums
                let filtered = albums.filter { album in
                    guard let releaseDateString = album.releaseDate else { return false }
                    guard let releaseDate = parseReleaseDate(releaseDateString) else { return false }
                    return releaseDate >= cutoffDate && !isCompilationAlbum(album.name)
                }
                
                recentAlbums.append(contentsOf: filtered)
                
                // Rate limiting: Small delay every 10 requests
                if (index + 1) % 10 == 0 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            } catch {
                print("⚠️ Failed to fetch albums for \(artist.name): \(error.localizedDescription)")
                continue
            }
        }
        
        return recentAlbums
    }
    
    // MARK: - Step 6: Extract Tracks from Albums
    
    private func extractTracksFromAlbums(albums: [SpotifyAlbum], token: String) async throws -> [SpotifyTrack] {
        var allTracks: [SpotifyTrack] = []
        var trackIdsSeen = Set<String>()
        
        for (index, album) in albums.enumerated() {
            do {
                let tracks = try await apiService.getAlbumTracks(albumId: album.id, token: token)
                
                // Deduplicate and add
                for var track in tracks {
                    if !trackIdsSeen.contains(track.id) {
                        // Enrich track with album info (album tracks endpoint doesn't include full album data)
                        track = SpotifyTrack(
                            spotifyId: track.spotifyId,
                            name: track.name,
                            artists: track.artists,
                            album: album, // Use the full album we already have
                            popularity: track.popularity,
                            previewUrl: track.previewUrl,
                            uri: track.uri,
                            durationMs: track.durationMs
                        )
                        allTracks.append(track)
                        trackIdsSeen.insert(track.id)
                    }
                }
                
                // Rate limiting: Small delay every 10 requests
                if (index + 1) % 10 == 0 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            } catch {
                print("⚠️ Failed to fetch tracks for album \(album.name): \(error.localizedDescription)")
                continue
            }
        }
        
        return allTracks
    }
    
    // MARK: - Scoring Engine
    
    private func scoreTracks(_ tracks: [SpotifyTrack], lowFollowerArtists: [SpotifyArtist], against profile: ListeningProfile) -> [HiddenGem] {
        // Create a dictionary for quick artist follower lookup
        let artistFollowerMap: [String: Int] = Dictionary(uniqueKeysWithValues: lowFollowerArtists.compactMap { artist in
            guard let followers = artist.followers?.total else { return nil }
            return (artist.id, followers)
        })
        
        return tracks.map { track in
            let score = calculateMatchScore(track: track, artistFollowerMap: artistFollowerMap, profile: profile)
            let reasons = generateMatchReasons(track: track, artistFollowerMap: artistFollowerMap, profile: profile)
            
            return HiddenGem(
                id: track.id,
                track: track,
                matchScore: score,
                matchReasons: reasons,
                streamCount: nil,
                popularity: track.popularity
            )
        }.sorted { $0.matchScore > $1.matchScore }
    }
    
    private func calculateMatchScore(track: SpotifyTrack, artistFollowerMap: [String: Int], profile: ListeningProfile) -> Double {
        var score = 0.0
        
        // 1. Follower Count Score (40 points) - Lower is better
        if let artistId = track.artists.first?.id,
           let followers = artistFollowerMap[artistId] {
            // Normalize: 0 followers = 40 points, 10k followers = 0 points
            let followerScore = max(0, 1.0 - (Double(followers) / Double(followerThreshold)))
            score += followerScore * 40.0
        }
        
        // 2. Recency Score (30 points)
        if let releaseDate = parseReleaseDate(track.album.releaseDate ?? "") {
            let daysSinceRelease = Calendar.current.dateComponents([.day], from: releaseDate, to: Date()).day ?? recencyDays
            // Normalize: 0 days = 30 points, 60 days = 15 points
            let recencyScore = max(0.5, 1.0 - (Double(daysSinceRelease) / Double(recencyDays * 2)))
            score += recencyScore * 30.0
        }
        
        // 3. Genre Match (20 points)
        let genreMatch = calculateGenreMatch(track: track, profile: profile)
        score += genreMatch * 20.0
        
        // 4. Popularity Bonus (10 points) - Lower is better
        let popularityBonus = max(0, (20.0 - Double(track.popularity)) / 20.0)
        score += popularityBonus * 10.0
        
        return min(score, 100.0)
    }
    
    private func calculateGenreMatch(track: SpotifyTrack, profile: ListeningProfile) -> Double {
        guard !profile.genreWeights.isEmpty else { return 0.5 }
        
        // Check if track's artist is in user's profile (related artist, so likely similar genre)
        let trackArtistIds = Set(track.artists.map { $0.id })
        let profileArtistIds = Set(profile.topArtists.map { $0.id })
        
        if !trackArtistIds.isDisjoint(with: profileArtistIds) {
            return 1.0 // Perfect match if artist is known
        }
        
        // Otherwise, assume moderate match (came from related artists, so should be relevant)
        return 0.7
    }
    
    // MARK: - Match Reasons
    
    private func generateMatchReasons(track: SpotifyTrack, artistFollowerMap: [String: Int], profile: ListeningProfile) -> [String] {
        var reasons: [String] = []
        
        // Follower count reason
        if let artistId = track.artists.first?.id,
           let followers = artistFollowerMap[artistId] {
            let followerString = formatFollowerCount(followers)
            reasons.append("Emerging artist (\(followerString) followers)")
        }
        
        // Recency reason
        if let releaseDate = parseReleaseDate(track.album.releaseDate ?? "") {
            let daysSinceRelease = Calendar.current.dateComponents([.day], from: releaseDate, to: Date()).day ?? 0
            if daysSinceRelease <= 7 {
                reasons.append("Released this week!")
            } else if daysSinceRelease <= 30 {
                reasons.append("Released \(daysSinceRelease) days ago")
            } else {
                reasons.append("Recent release")
            }
        }
        
        // Genre/Artist match
        for artist in track.artists {
            if profile.topArtists.contains(where: { $0.id == artist.id }) {
                reasons.append("You love \(artist.name)")
                break
            }
        }
        
        // If no artist match, mention it's similar
        if !reasons.contains(where: { $0.contains("You love") }) {
             reasons.append("Similar to your taste")
        }
        
        return Array(reasons.prefix(3))
    }
    
    // MARK: - Helper Functions
    
    private func parseReleaseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        
        // Try full date format first (YYYY-MM-DD)
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try year-month format (YYYY-MM)
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try year only (YYYY)
        formatter.dateFormat = "yyyy"
        return formatter.date(from: dateString)
    }
    
    private func formatFollowerCount(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fK", thousands)
        }
    }
    
    private func isMainstreamArtist(_ artistName: String) -> Bool {
        let mainstream = [
            "gorillaz", "beatles", "rolling stones", "led zeppelin",
            "pink floyd", "queen", "eagles", "fleetwood mac",
            "nirvana", "radiohead", "foo fighters", "red hot chili peppers",
            "coldplay", "u2", "metallica", "ac/dc", "guns n' roses",
            "david bowie", "the who", "the doors", "jimi hendrix",
            "bob dylan", "bruce springsteen", "prince", "michael jackson",
            "madonna", "beyonce", "taylor swift", "drake", "kanye west",
            "ed sheeran", "adele", "rihanna", "eminem", "jay-z"
        ]
        return mainstream.contains(artistName)
    }
    
    private func isCompilationAlbum(_ albumName: String) -> Bool {
        let compilationKeywords = [
            "best of", "greatest hits", "compilation", "collection",
            "90s hits", "00s hits", "10s hits", "20s hits",
            "indie rock non stop", "classic", "essential", "ultimate",
            "hits", "anthology", "complete", "definitive"
        ]
        
        let lowerName = albumName.lowercased()
        return compilationKeywords.contains(where: { lowerName.contains($0) })
    }
}
