//
//  EnhancedHiddenGemsDiscovery.swift
//  HiddenJams
//
//  Multi-API discovery engine with Last.fm, MusicBrainz, and Every Noise integration
//  All recommendations cross-referenced with Spotify for playback
//

import Foundation
import Combine

class EnhancedHiddenGemsDiscovery: ObservableObject {
    @Published var discoveredGems: [RecommendedTrack] = []
    @Published var isDiscovering = false
    @Published var errorMessage: String?
    @Published var discoveryProgress: String = ""
    
    // Services
    private let spotifyAPI: SpotifyAPIService
    private let lastFmService: LastFmService
    private let musicBrainzService: MusicBrainzService
    private let everyNoiseService: EveryNoiseService
    private let crossReferenceService: SpotifyCrossReferenceService
    private let aiExplainer: AIMatchExplainer
    private let openAIService = OpenAIService()
    private let artistFirst = ArtistFirstDiscovery()

    /// The obscurity window for the run in progress, derived from the slider.
    private var currentWindow = ObscurityWindow(level: 0.25)
    
    // Discovery Settings
    private var popularityThreshold = 50  // Tracks below this popularity score (raised from 30)
    private var followerThreshold = 50_000  // Artists with fewer followers (raised from 15k)
    private var recencyMonths = 12  // Tracks from last N months
    
    // Relaxed settings for genres with limited Spotify search support
    private func getPopularityThreshold(for genres: [String]) -> Int {
        let dnbGenres: Set<String> = ["drum-and-bass", "drum and bass", "dnb", "jungle", "liquid funk", "neurofunk"]
        let acousticGenres: Set<String> = ["folk", "folk rock", "indie folk", "acoustic", "singer-songwriter", "americana", "bluegrass"]
        let genresSet = Set(genres.map { $0.lowercased() })
        if !genresSet.isDisjoint(with: dnbGenres) {
            return 60  // Relaxed for DnB since we use electronic fallback
        }
        if !genresSet.isDisjoint(with: acousticGenres) {
            return 55  // Relaxed for folk/acoustic genres
        }
        return 50  // Normal threshold (raised from 30)
    }
    
    // Genre normalization: Maps user-friendly names to Spotify's exact genre names
    private let genreNameMapping: [String: String] = [
        // These are matched against Spotify ARTIST genres, which use spaces.
        // (The hyphenated spellings that used to live here — "drum-and-bass",
        // "hip-hop", "r-n-b" — were seed names for the /recommendations
        // endpoint Spotify retired in 2024, and they match nothing in search.
        // Searching for the hyphenated form returned zero artists, which is
        // what the old "DnB mode" workaround was compensating for.)
        "drum and bass": "drum and bass",
        "dnb": "drum and bass",
        "d&b": "drum and bass",
        "hip hop": "hip hop",
        "r&b": "r&b",
        "k-pop": "k-pop",
        "indie": "indie",
        "alternative": "alternative",
        "electronic": "electronic",
        "dance": "edm",  // Spotify uses "edm" not "dance"
        "world": "world",
        "ambient": "ambient",
        "experimental": "experimental",
        "jungle": "jungle",  // Jungle is separate genre in Spotify
        "pop": "pop",
        "rock": "rock",
        "metal": "metal",
        "punk": "punk",
        "jazz": "jazz",
        "classical": "classical",
        "folk": "folk",
        "country": "country",
        "latin": "latin",
        "reggae": "reggae",
        "blues": "blues",
        "soul": "soul",
        "funk": "funk",
        "gospel": "gospel",
        "christian": "christian",
        "worship": "ccm",  // Contemporary Christian Music
        "reggaeton": "reggaeton",
        "anime": "anime",
        "children's music": "kids"
    ]
    
    // MARK: - Genre Families for Intelligent Matching
    // Maps broad genres to all their sub-genres so "electronic" can match "idm", "glitch", etc.
    private let genreFamilies: [String: Set<String>] = {
        // Define family sets
        let electronicFamily: Set<String> = [
            "electronic", "edm", "idm", "techno", "house", "trance",
            "ambient", "drone", "glitch", "trip hop", "downtempo",
            "chillwave", "vaporwave", "witch house", "future bass",
            "hypnagogic pop", "dubstep", "drum and bass", "breakbeat",
            "electro", "synth", "dub techno", "uk funky", "ballroom vogue",
            "chillstep", "footwork", "melodic techno", "tech house",
            "progressive house", "bass house", "psytrance", "minimal techno",
            "deep house", "progressive trance", "future house",
            "lo-fi", "lo-fi beats", "lo-fi hip hop",  // Lo-fi is electronic!
            "dnb", "jungle", "liquid funk", "neurofunk", "drum n bass"  // DnB family!
        ]
        
        let hipHopFamily: Set<String> = [
            "hip hop", "rap", "trap", "boom bap", "conscious hip hop",
            "underground hip hop", "lo-fi hip hop", "instrumental hip hop",
            "hip-hop", "lo-fi beats", "lo-fi"
        ]
        
        return [
            // Map both normalized and display names to same family
            "electronic": electronicFamily,
            "edm": electronicFamily,  // Normalized name for "Dance"
            "dance": electronicFamily,
            
            "rock": [
                "rock", "indie rock", "alternative rock", "punk", "post-punk",
                "garage rock", "psychedelic rock", "space rock", "noise rock",
                "post-rock", "shoegaze", "grunge", "hard rock", "metal",
                "indie", "alternative", "post-grunge", "avant-garde"
            ],
            
            "hip hop": hipHopFamily,
            "rap": hipHopFamily,  // Normalized name
            
            "jazz": [
                "jazz", "bebop", "cool jazz", "free jazz", "nu jazz",
                "jazz fusion", "smooth jazz", "acid jazz"
            ],
            
            "pop": [
                "pop", "indie pop", "synth pop", "electropop", "dream pop",
                "k-pop", "j-pop"
            ],
            
            "folk": [
                "folk", "indie folk", "folk rock", "americana", "bluegrass",
                "singer-songwriter", "roots rock", "freak folk", "psych folk",
                "chamber folk", "neofolk", "anti-folk", "new weird america",
                "acoustic", "fingerstyle", "stomp and holler", "traditional folk",
                "contemporary folk", "nordic folk", "celtic", "appalachian",
                "folk punk", "progressive folk", "psychedelic folk", "world folk"
            ],
            
            // DnB family - all variants map to the same set!
            "drum and bass": electronicFamily,
            "drum-and-bass": electronicFamily,
            "dnb": electronicFamily,
            "jungle": electronicFamily
        ]
    }()
    
    private var knownTrackIds: Set<String> = []
    private var userLibrary: [SpotifyTrack] = []  // For AI explanations
    
    // MARK: - DnB Mode Flag (persists through discovery flow)
    // This flag is set when user selects a DnB genre and ensures relaxed filters throughout
    private var isDnBMode: Bool = false
    
    // MARK: - Session-Based Deduplication (for "Discover More" within same session)
    private var sessionSeenTracks: Set<String> = []  // Tracks seen in THIS discovery session only
    private var sessionSeenArtists: Set<String> = []  // Artists seen in THIS discovery session only
    
    
    init() {
        self.spotifyAPI = SpotifyAPIService()
        self.lastFmService = LastFmService()
        self.musicBrainzService = MusicBrainzService()
        self.everyNoiseService = EveryNoiseService()
        self.crossReferenceService = SpotifyCrossReferenceService(spotifyAPI: spotifyAPI)
        self.aiExplainer = AIMatchExplainer()
    }
    
    private let seasonalGenres = [
        "christmas", "holiday", "halloween", "easter", "valentines",
        "new year", "thanksgiving", "hanukkah", "kwanzaa"
    ]
    
    // MARK: - Main Discovery Function
    
    func discoverHiddenGems(
        profile: ListeningProfile,
        userTracks: [String],
        userLibrary: [SpotifyTrack],
        selectedGenres: Set<String>? = nil, // NEW: Strict Genre Filter
        token: String,
        count: Int = 25,
        appendResults: Bool = false,  // NEW: Append to existing gems instead of replacing
        popularityOverride: Int? = nil,  // User-controlled popularity threshold from slider
        followerOverride: Int? = nil,    // User-controlled follower threshold from slider
        obscurityLevel: Double? = nil    // Raw slider position, 0.0 (obscure) → 1.0 (mainstream)
    ) async {
        // The slider position is the source of truth for how obscure results
        // should be. The two older override parameters are kept so existing
        // callers keep working, and are used to reconstruct a window when no
        // raw level is supplied.
        if let level = obscurityLevel {
            currentWindow = ObscurityWindow(level: level)
        } else if let popularity = popularityOverride {
            currentWindow = ObscurityWindow(level: min(max(Double(popularity) / 100.0, 0.0), 1.0))
        }

        popularityThreshold = popularityOverride ?? currentWindow.popularityCeiling
        followerThreshold = followerOverride ?? currentWindow.followerCeiling

        print("🎚️ \(currentWindow.label): ≤\(currentWindow.followerDescription), popularity ≤\(currentWindow.popularityCeiling)")
        
        await MainActor.run {
            isDiscovering = true
            isDnBMode = false  // Reset DnB mode flag for each discovery session
            // Only clear if not appending
            if !appendResults {
                discoveredGems = []
                // Clear session-based deduplication for fresh discovery
                sessionSeenTracks.removeAll()
                sessionSeenArtists.removeAll()
            }
            knownTrackIds = Set(userTracks)
            self.userLibrary = userLibrary
            if let selected = selectedGenres, !selected.isEmpty {
                discoveryProgress = "Focused Discovery: \(selected.joined(separator: ", "))"
            } else {
                discoveryProgress = "Starting deep discovery..."
            }
        }
        
        do {
            print("🎯 Deep Discovery Mode")
            print("📊 Using popularity threshold: \(popularityThreshold)")
            var activeGenres = profile.genreWeights.keys.map { $0 }
            
            // STRICT MODE: Determine active genres
            let strictMode = (selectedGenres != nil && !selectedGenres!.isEmpty)
            
            // The previous build special-cased drum & bass here: it forced the
            // genre list to ["drum-and-bass", "electronic", "jungle"] and set
            // strictMode = false, which switched OFF genre filtering for the
            // whole run. That is why unrelated tracks — country songs, random
            // pop — turned up in DnB results.
            //
            // The underlying problem was the genre spelling above, not DnB
            // itself, so the override is gone and every genre now takes the
            // same path with filtering left on.
            
            if strictMode {
                activeGenres = Array(selectedGenres!)
                print("🔒 STRICT FILTER ACTIVE: Restricted to \(activeGenres)")
            } else {
                print("🌍 OPEN MODE: Using top profile genres")
            }
            
            // Normalize genre names to match Spotify's naming convention
            activeGenres = activeGenres.map { normalizeGenreName($0) }
            print("🎵 Normalized genres: \(activeGenres)")
            
            print("📊 Criteria: popularity<\(popularityThreshold), followers<\(followerThreshold/1000)k, last 12 months")
            print("🧠 AI Explanations: Comparing to \(userLibrary.count) tracks in your library")
            
            var allCandidates: [SpotifyTrack] = []

            // BRANCH A (primary): artist-first search.
            //
            // Finds artists inside the slider's follower/popularity window and
            // takes their top tracks. This is the branch that actually delivers
            // the product promise — "obscure artists in this genre" — because it
            // filters on the artist, not on individual track popularity.
            await updateProgress("Finding \(currentWindow.label.lowercased()) artists...")
            let obscureArtists = await artistFirst.findArtists(
                genres: activeGenres,
                window: currentWindow,
                excludedArtistIds: sessionSeenArtists,
                targetCount: 60,
                token: token,
                progress: { [weak self] message in
                    Task { await self?.updateProgress(message) }
                }
            )
            print("✅ Artist-first: \(obscureArtists.count) artists under \(currentWindow.followerDescription)")

            // Narrow genres can come back thin at the obscure end of the slider.
            // Widening the window once beats showing the user an empty screen.
            var artistPool = obscureArtists
            if artistPool.count < 10 {
                let widened = currentWindow.relaxed()
                print("↔️ Only \(artistPool.count) artists; widening to \(widened.followerDescription)")
                await updateProgress("Widening the search...")

                let extra = await artistFirst.findArtists(
                    genres: activeGenres,
                    window: widened,
                    excludedArtistIds: sessionSeenArtists,
                    targetCount: 40,
                    token: token,
                    progress: { [weak self] message in
                        Task { await self?.updateProgress(message) }
                    }
                )

                // Keep the originals first so the most obscure still lead.
                var seen = Set(artistPool.compactMap { $0.spotifyId })
                for artist in extra {
                    guard let id = artist.spotifyId, !seen.contains(id) else { continue }
                    seen.insert(id)
                    artistPool.append(artist)
                }
                print("↔️ Pool now \(artistPool.count) artists")
            }

            if !artistPool.isEmpty {
                await updateProgress("Collecting their tracks...")
                let artistTracks = await artistFirst.tracks(
                    for: Array(artistPool.prefix(40)),
                    maxPerArtist: 2,
                    token: token,
                    progress: { [weak self] message in
                        Task { await self?.updateProgress(message) }
                    }
                )
                print("✅ Artist-first: \(artistTracks.count) tracks")
                allCandidates.append(contentsOf: artistTracks)
            }

            // BRANCH B: genre track search — broadens the pool beyond the
            // artists that surfaced in artist search.
            await updateProgress("Searching Spotify (Main Genres)...")
            let genreCandidates = try await discoverViaSpotifyHipster(
                profile: profile,
                activeGenres: activeGenres,
                token: token
            )
            print("✅ Genre searches: Found \(genreCandidates.count) candidates")
            allCandidates.append(contentsOf: genreCandidates)

            // BRANCH C: similarity, seeded from the user's own library via Last.fm.
            await updateProgress("Following similar artists...")
            let similarCandidates = try await discoverViaSimilarArtists(
                profile: profile,
                activeGenres: activeGenres,
                window: currentWindow,
                token: token
            )
            print("✅ Similarity discovery: Found \(similarCandidates.count) candidates")
            allCandidates.append(contentsOf: similarCandidates)

            // BRANCH D: micro-genre deep dive.
            await updateProgress("Searching Micro-Genres (Deep Dive)...")
            let microCandidates = try await discoverViaMicroGenres(
                profile: profile,
                activeGenres: activeGenres,
                token: token,
                limit: 100
            )
            print("✅ Micro-genre searches: Found \(microCandidates.count) candidates")
            allCandidates.append(contentsOf: microCandidates)
            
            // Remove duplicates
            allCandidates = deduplicateTracks(allCandidates)
            print("📦 Total unique candidates: \(allCandidates.count)")
            
            // Apply filters (OPTIMIZED - batch check)
            await updateProgress("Filtering gems...")
            // Apply filters (OPTIMIZED - batch check)
            await updateProgress("Filtering gems...")
            // If strict mode is active, we must also allow the micro-genres that we are about to search for
            // Otherwise, the strict filter will reject the very tracks we find in the micro-genre step.
            var validationGenres = Set(activeGenres) // Convert to Set for formUnion
            if strictMode { // Only expand if strict mode is active
                let expandedStart = Date()
                let microGenres = everyNoiseService.getMicroGenres(fromGenres: Array(activeGenres))
                // Add top 20 micro-genres to allow-list (matching the search limit)
                validationGenres.formUnion(microGenres.prefix(20))
                print("🔓 Expanded strict filter to include \(microGenres.prefix(20).count) micro-genres")
            }
            
            // 3. Apply Filters (Popularity, Blacklist, Language, Duplicates)
            // Pass the EXPANDED validation genres so we don't reject valid findings
            var filteredCandidates = try await applyFastFilters(
                tracks: allCandidates,
                selectedGenres: validationGenres.isEmpty ? nil : validationGenres,
                activeGenres: activeGenres,
                token: token
            )
            print("✨ Filtered to \(filteredCandidates.count) hidden gems")
            
            // PROGRESSIVE RELAXATION: If we don't have enough tracks, relax thresholds
            let minimumRequired = 25
            var relaxationAttempts = 0
            let maxRelaxationAttempts = 2
            
            while filteredCandidates.count < minimumRequired && relaxationAttempts < maxRelaxationAttempts {
                relaxationAttempts += 1
                
                // Double the thresholds for each relaxation attempt
                popularityThreshold = min(popularityThreshold * 2, 80)  // Cap at 80
                followerThreshold = followerThreshold * 2               // Double followers
                
                print("⚠️ Only \(filteredCandidates.count) tracks passed filters (need \(minimumRequired))")
                print("🔄 Relaxation attempt \(relaxationAttempts): popularity<\(popularityThreshold), followers<\(followerThreshold/1000)k")
                
                // Re-filter with relaxed thresholds
                filteredCandidates = try await applyFastFilters(
                    tracks: allCandidates,
                    selectedGenres: validationGenres.isEmpty ? nil : validationGenres,
                    activeGenres: activeGenres,
                    token: token
                )
                print("✨ After relaxation: \(filteredCandidates.count) hidden gems")
                
                // Restore original thresholds for next discovery session
                // (but keep relaxed for this filtering round)
            }
            
            // Score first, THEN fetch preview URLs only for top candidates
            await updateProgress("Scoring tracks...")
            
            // NEW: Vector Similarity Ranking
            var vectorScores: [String: Double] = [:]
            if let tasteVector = profile.tasteVector {
                await updateProgress("AI Ranking: Comparing to your taste vector...")
                if let scores = try? await rankByVectorSimilarity(tracks: filteredCandidates, tasteVector: tasteVector) {
                    vectorScores = scores
                    print("✅ Ranked \(scores.count) tracks by vector similarity")
                }
            }
            
            let scored = scoreAndRankWithExplanations(
                tracks: filteredCandidates,
                profile: profile,
                vectorScores: vectorScores
            )
            // Increased to 100 to account for artist deduplication reducing count
            let topCandidates = Array(scored.prefix(100))  // Fetch preview URLs for top 100 (will dedupe artists)
            
            print("🎯 Fetching preview URLs for top \(topCandidates.count) tracks...")
            await updateProgress("Checking which tracks are playable...")
            
            let enrichedTracks = try await enrichTracksWithDetails(
                tracks: topCandidates.map { $0.track },
                token: token
            )
            
            let withPreviews = enrichedTracks.filter { $0.previewUrl != nil }.count
            print("🎵 \(withPreviews) tracks have working previews (out of \(enrichedTracks.count))")
            
            // Re-score the enriched tracks
            let finalRecommendations = scored.compactMap { rec -> RecommendedTrack? in
                // Find the enriched version of this track
                guard let enriched = enrichedTracks.first(where: { $0.id == rec.track.id }) else {
                    return nil
                }
                
                // Return updated recommendation with enriched track data
                // Return updated recommendation with enriched track data
                return RecommendedTrack(
                    id: rec.id,
                    spotifyURI: enriched.uri,
                    track: enriched, // Use the version that might have a preview URL now
                    matchScore: rec.matchScore,
                    obscurityScore: rec.obscurityScore,
                    recencyScore: rec.recencyScore,
                    totalScore: rec.totalScore,
                    obscurityReason: rec.obscurityReason,
                    matchExplanation: rec.matchExplanation,
                    similarToTrack: rec.similarToTrack,
                    similarityReasons: rec.similarityReasons
                )
            }
            
            let topRecommendations = Array(finalRecommendations.prefix(count))
            
            print("🎉 Discovery complete: \(topRecommendations.count) recommendations with AI explanations")
            
            await MainActor.run {
                let finalResults = appendResults ? discoveredGems + topRecommendations : topRecommendations
                discoveredGems = finalResults
                
                // Mark discovered tracks/artists as session-seen (prevents duplication in "Discover More")
                for gem in topRecommendations {
                    sessionSeenTracks.insert(gem.track.id)
                    if let artistId = gem.track.artists.first?.id {
                        sessionSeenArtists.insert(artistId)
                    }
                }
                
                // Also add to persistent history (for next full discovery session)
                let allArtistIds = Set(topRecommendations.flatMap { $0.track.artists.compactMap { $0.id } })
                DiscoveryHistoryManager.shared.addToHistory(
                    trackIds: topRecommendations.map { $0.track.id },
                    artistIds: Array(allArtistIds)
                )
                
                isDiscovering = false
                discoveryProgress = "Complete!"
            }
            
        } catch {
            print("❌ Discovery error: \(error)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isDiscovering = false
                self.discoveryProgress = "Error occurred"
            }
        }
    }
    
    // MARK: - Genre Normalization
    
    /// Normalize genre names to match Spotify's exact naming convention
    /// - Parameter genre: User-friendly genre name
    /// - Returns: Spotify-compatible genre name
    private func normalizeGenreName(_ genre: String) -> String {
        let lowercased = genre.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check mapping first
        if let spotifyName = genreNameMapping[lowercased] {
            return spotifyName
        }
        
        // If not in mapping, return lowercase version
        // Spotify genres are typically lowercase
        return lowercased
    }
    
    // MARK: - Branch A: Last.fm Discovery
    
    private func discoverViaLastFm(profile: ListeningProfile, token: String) async throws -> [SpotifyTrack] {
        var candidates: [SpotifyTrack] = []
        
        // Get top artists from profile
        let topArtists = Array(profile.topArtists.prefix(10))
        
        for artist in topArtists {
            do {
                // Get similar artists from Last.fm
                let similarArtists = try await lastFmService.getSimilarArtists(
                    artistName: artist.name,
                    limit: 20
                )
                
                // Cross-reference with Spotify
                for lastFmArtist in similarArtists {
                    guard let spotifyMatch = try await crossReferenceService.findSpotifyArtist(
                        name: lastFmArtist.name,
                        token: token
                    ) else { continue }
                    
                    // Filter: obscure artists only
                    guard spotifyMatch.isObscure else { continue }
                    
                    // Get TOP TRACK for the artist
                    do {
                        let topTracks = try await spotifyAPI.getArtistTopTracks(
                            artistId: spotifyMatch.spotifyID,
                            token: token
                        )
                        
                        if let topTrack = topTracks.first {
                            candidates.append(topTrack)
                        }
                    } catch {
                        print("⚠️ Failed to get top tracks for \(artist.name): \(error)")
                        continue
                    }
                }
                
                // Rate limiting
                try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                
            } catch {
                print("⚠️ Last.fm error for \(artist.name): \(error)")
                continue
            }
        }
        
        return candidates
    }
    
    // MARK: - Simple Genre-Based Discovery (WORKS!)
    
    // MARK: - Simple Genre-Based Discovery (WORKS!)
    
    private func discoverViaSpotifyHipster(profile: ListeningProfile, activeGenres: [String], token: String) async throws -> [SpotifyTrack] {
        var candidates: [SpotifyTrack] = []
        
        // SPECIAL DnB HANDLING: Spotify search doesn't support genre:"drum-and-bass" well
        // Use electronic genre filter + DnB-specific terms instead of plain label names
        if self.isDnBMode {
            // Use genre:electronic combined with DnB-specific terms
            // This prevents returning "Hospital Bed" by country singers or "Medicine" by random artists
            let dnbSearchTerms = [
                "genre:electronic dnb",
                "genre:electronic drum and bass",
                "genre:electronic liquid funk",
                "genre:electronic neurofunk",
                "genre:electronic jungle",
                "genre:electronic breakbeat",
                "genre:electronic 170 bpm",
                "genre:electronic bassline",
            ]
            
            print("🎵 DnB Mode: Using genre:electronic + DnB keywords for proper filtering")
            
            for term in dnbSearchTerms.shuffled().prefix(6) {
                do {
                    let randomOffset = Int.random(in: 0...200)
                    print("   🎲 DnB Searching '\(term)' with offset \(randomOffset)")
                    
                    let tracks = try await spotifyAPI.searchTracks(
                        query: term,
                        limit: 50,
                        offset: randomOffset,
                        market: "from_token",
                        token: token
                    )
                    
                    candidates.append(contentsOf: tracks)
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                } catch {
                    print("⚠️ DnB search error for \(term): \(error)")
                    continue
                }
            }
            
            print("✅ DnB search found \(candidates.count) candidates")
            return candidates
        }
        
        // Standard genre search for non-DnB
        // Search multiple pages per genre to ensure enough candidates
        let searchGenres = activeGenres.prefix(10)
        print("🎯 Using genres: \(Array(searchGenres))")
        
        for genre in searchGenres {
            // Search 3 different offset ranges per genre for more candidates
            let offsets = [
                Int.random(in: 0...200),
                Int.random(in: 200...400),
                Int.random(in: 400...600)
            ]
            
            for (index, offset) in offsets.enumerated() {
                do {
                    let query = "genre:\"\(genre)\""
                    
                    print("   🎲 Searching '\(genre)' page \(index + 1)/3 with offset \(offset)")
                    
                    let tracks = try await spotifyAPI.searchTracks(
                        query: query,
                        limit: 50,
                        offset: offset,
                        market: "from_token",
                        token: token
                    )
                    
                    candidates.append(contentsOf: tracks)
                    try await Task.sleep(nanoseconds: 150_000_000) // 0.15s
                    
                } catch {
                    print("⚠️ Search error for \(genre) offset \(offset): \(error)")
                    continue
                }
            }
        }
        
        print("✅ Found \(candidates.count) candidates from genre searches")
        return candidates
    }
    
    // MARK: - Branch C: Micro-Genre Discovery
    
    // MARK: - Branch C: Micro-Genre Discovery
    
    private func discoverViaMicroGenres(profile: ListeningProfile, activeGenres: [String], token: String, limit: Int = 50) async throws -> [SpotifyTrack] {
        var candidates: [SpotifyTrack] = []
        
        // Use passed active genres (already strict filtered)
        let seedGenres = activeGenres.prefix(5)
        
        
        // Expand to micro-genres
        let microGenres = everyNoiseService.getMicroGenres(fromGenres: Array(seedGenres))
        print("🎵 Exploring \(microGenres.count) micro-genres from seed: \(seedGenres)")
        
        // Search each micro-genre (limit 30 tracks per genre to ensure depth)
        for genre in microGenres.prefix(5) {
            // Skip if micro-genre is seasonal
            let lower = genre.lowercased()
            if seasonalGenres.contains(where: { lower.contains($0) }) {
                continue
            }
            
            do {
                print("🔍 Searching Spotify: genre:\"\(genre)\"")
                let tracks = try await spotifyAPI.searchTracks(
                    query: "genre:\"\(genre)\"", 
                    limit: 30, // Increased depth per genre
                    offset: Int.random(in: 0...100), // Increased range for more diversity
                    token: token
                )
                
                candidates.append(contentsOf: tracks)
                
                // Rate limiting
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            } catch {
                print("⚠️ Micro-genre search error for \(genre): \(error)")
                continue
            }
        }
        
        return candidates
    }
    
    // Spotify's /recommendations endpoint was removed in November 2024.
    // Seeding now happens through artist search and Last.fm similarity instead.

    
    // MARK: - Artist-Based Discovery
    
    /// Discovery by similarity, seeded from the user's own listening.
    ///
    /// Replaces the previous version, which called Spotify's Related Artists
    /// endpoint (removed by Spotify in November 2024) and seeded it from three
    /// hardcoded lists of artist names — drum & bass, electronic and folk.
    /// Any other genre fell straight through to an empty result.
    ///
    /// Similarity now comes from Last.fm, and the seeds come from the user's
    /// own top artists in the selected genres, so it works for every genre and
    /// the results are anchored to taste rather than to a list someone typed in.
    private func discoverViaSimilarArtists(
        profile: ListeningProfile,
        activeGenres: [String],
        window: ObscurityWindow,
        token: String
    ) async throws -> [SpotifyTrack] {

        let genreSet = Set(activeGenres.map { $0.lowercased() })

        // Prefer the user's own artists that sit in the selected genres.
        var seeds = profile.topArtists
            .filter { artist in
                artist.genres.contains { genre in
                    let lower = genre.lowercased()
                    return genreSet.contains(where: { lower.contains($0) || $0.contains(lower) })
                }
            }
            .sorted { $0.influence > $1.influence }
            .map { $0.name }

        // If nothing in the library matches the chosen genres, fall back to the
        // user's strongest artists overall — still better than a fixed list.
        if seeds.isEmpty {
            seeds = profile.topArtists
                .sorted { $0.influence > $1.influence }
                .prefix(5)
                .map { $0.name }
        }

        guard !seeds.isEmpty else {
            print("ℹ️ No seed artists available for similarity discovery")
            return []
        }

        let seedSelection = Array(seeds.prefix(8).shuffled().prefix(4))
        print("🔗 Similarity seeds: \(seedSelection.joined(separator: ", "))")

        let similar = await artistFirst.similarArtists(
            toArtistsNamed: seedSelection,
            window: window,
            excludedArtistIds: sessionSeenArtists,
            token: token
        )

        print("🔍 Last.fm similarity produced \(similar.count) artists inside the window")

        guard !similar.isEmpty else { return [] }

        let allTracks = await artistFirst.tracks(
            for: Array(similar.prefix(20)),
            maxPerArtist: 2,
            token: token
        )

        print("✅ Similarity discovery found \(allTracks.count) tracks")
        return allTracks
    }
    
    // MARK: - Check Preview URLs (Fast)
    
    // MARK: - Check Preview URLs (Fast)
    
    /// Fills in full track detail and attaches a preview URL where one can be found.
    ///
    /// Two things changed here, both of which were costing results:
    ///
    /// 1. **Tracks without a preview are no longer discarded.** Spotify stopped
    ///    populating `preview_url` for most apps in its November 2024 API
    ///    changes, so previews now come from iTunes or Deezer — and the more
    ///    obscure an artist is, the less likely either service carries them.
    ///    Filtering on preview availability therefore threw away precisely the
    ///    undiscovered artists this app exists to surface. Tracks are now
    ///    returned either way; playable ones simply sort first.
    ///
    /// 2. **Track detail is fetched in batches of 50** via `/v1/tracks?ids=`
    ///    rather than one request per track. For 100 candidates that is 2
    ///    requests instead of 100.
    private func enrichTracksWithDetails(tracks: [SpotifyTrack], token: String) async throws -> [SpotifyTrack] {
        guard !tracks.isEmpty else { return [] }

        let itunesService = ItunesPreviewService()
        let deezerService = DeezerPreviewService()

        print("🔍 Enriching \(tracks.count) tracks (batched)...")

        // 1. Batch-fetch full track objects.
        let ids = tracks.compactMap { $0.spotifyId }
        var detailed: [SpotifyTrack]
        do {
            detailed = try await spotifyAPI.getTracks(ids: ids, market: "from_token", token: token)
        } catch {
            print("⚠️ Batch track fetch failed, using search results as-is: \(error)")
            detailed = tracks
        }

        if detailed.isEmpty { detailed = tracks }

        // 2. Look up previews concurrently for the ones Spotify didn't supply.
        let needingPreview = detailed.filter { $0.previewUrl == nil }
        print("🎧 \(detailed.count - needingPreview.count) had Spotify previews; looking up \(needingPreview.count) externally")

        var externalPreviews: [String: String] = [:]

        for batch in needingPreview.chunked(into: 10) {
            await withTaskGroup(of: (String, String?).self) { group in
                for track in batch {
                    group.addTask {
                        let artist = track.artists.first?.name ?? ""
                        if let itunes = await itunesService.findPreview(for: track.name, artist: artist) {
                            return (track.id, itunes)
                        }
                        if let deezer = await deezerService.findPreview(for: track.name, artist: artist) {
                            return (track.id, deezer)
                        }
                        return (track.id, nil)
                    }
                }

                for await (trackId, preview) in group {
                    if let preview = preview {
                        externalPreviews[trackId] = preview
                    }
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000)
        }

        // 3. Merge previews back in, keeping every track.
        let enriched = detailed.map { track -> SpotifyTrack in
            guard track.previewUrl == nil, let preview = externalPreviews[track.id] else {
                return track
            }
            return SpotifyTrack(
                spotifyId: track.spotifyId,
                name: track.name,
                artists: track.artists,
                album: track.album,
                popularity: track.popularity,
                previewUrl: preview,
                uri: track.uri,
                durationMs: track.durationMs
            )
        }

        // 4. Playable first — but nothing is dropped. Anything without a preview
        //    still opens in Spotify, which plays the full track anyway.
        let playable = enriched.filter { $0.previewUrl != nil }
        let unplayable = enriched.filter { $0.previewUrl == nil }

        print("🎵 \(playable.count) previewable, \(unplayable.count) Spotify-only (kept)")

        return playable + unplayable
    }
    
    // MARK: - Filtering
    
    // MARK: - Filtering
    
    // Fast filtering - NOW INCLUDES BATCH ARTIST CHECK & DEEP SCAN
    private func applyFastFilters(tracks: [SpotifyTrack], selectedGenres: Set<String>?, activeGenres: [String], token: String) async throws -> [SpotifyTrack] {
        // Strict Mode Flag - DISABLED for DnB mode!
        // In DnB mode, we want to allow tracks from neurofunk, liquid funk, etc without strict validation
        let strictMode = (selectedGenres != nil && !selectedGenres!.isEmpty) && !self.isDnBMode
        let allowedKeywords = strictMode ? selectedGenres! : []
        
        if self.isDnBMode {
            print("🎵 DnB Filter Mode: Strict genre validation DISABLED")
        }
        
        // Get excluded genres (Standard Blacklist)
        var excludedGenres = getExcludedGenres()
        
        // Global Artist Blacklist (Persistent Offenders)
        let bannedArtistNames = ["Happy Pills"]
        
        // If in Strict Mode, un-blacklist any genre that the user explicitly selected
        if strictMode {
            excludedGenres = excludedGenres.filter { excluded in
                // Keep exclusion only if it DOES NOT match any allowed keyword
                !allowedKeywords.contains { allowed in
                    // 1. Standard containment: "indie rock" contains "rock"
                    if allowed.lowercased().contains(excluded.lowercased()) { return true }
                    
                    // 2. Reverse containment: "psychedelic rock" contains "psychedelic" (from "neo-psychedelic")
                    let artistWords = Set(allowed.lowercased().split(separator: " ").map(String.init))
                    let excludedWords = Set(excluded.lowercased().split(separator: " ").map(String.init))
                    let intersection = artistWords.intersection(excludedWords)
                    return intersection.contains { $0.count > 3 }
                }
            }
        }
        
        let isLatinExcluded = excludedGenres.contains { $0.lowercased().contains("latin") || $0.lowercased().contains("spanish") }
        
        // NOTE: Deep Scan feature has been disabled due to Spotify API deprecation
        // The isLatinExcluded flag is kept for future use if API becomes available
        
        // 1. Basic pre-filter (local data only)
        var rejectionStats: [String: Int] = [:]
        let preFiltered = tracks.filter { track in
            // Filter 1: Not already known
            guard !knownTrackIds.contains(track.id) else { 
                rejectionStats["in_library"] = (rejectionStats["in_library"] ?? 0) + 1
                return false 
            }
            
            // Filter 1b: Not seen in THIS session (for "Discover More")
            guard !sessionSeenTracks.contains(track.id) else {
                rejectionStats["seen_track"] = (rejectionStats["seen_track"] ?? 0) + 1
                return false
            }
            
            // Filter 1c: Not seen in previous discovery sessions (Persistent Check)
            guard !DiscoveryHistoryManager.shared.isSeen(trackId: track.id) else { 
                rejectionStats["seen_track"] = (rejectionStats["seen_track"] ?? 0) + 1
                return false 
            }
            
            // Filter 1d: Artist not seen in THIS session (same session only - Fix #4)
            if let artistId = track.artists.first?.id {
                guard !sessionSeenArtists.contains(artistId) else {
                    rejectionStats["seen_artist"] = (rejectionStats["seen_artist"] ?? 0) + 1
                    return false
                }
            }
            
            // Filter 1d: Artist not seen in persistent history (Re-enabled)
            // STRICT CHECK: Reject if ANY artist on the track has been seen
            if track.artists.contains(where: { DiscoveryHistoryManager.shared.isArtistSeen(artistId: $0.id) }) {
                rejectionStats["seen_artist_history"] = (rejectionStats["seen_artist_history"] ?? 0) + 1
                return false
            }
            
            // Filter 2: Track popularity, with headroom above the artist ceiling.
            //
            // Obscurity is now judged on the ARTIST (followers + popularity) in
            // ArtistFirstDiscovery, which is the meaningful unit — a 400-follower
            // artist is undiscovered no matter how their best track scores.
            // Re-applying the artist's ceiling to individual tracks threw those
            // artists' one decent track away, so this keeps a 25-point margin and
            // only catches outright hits that slipped in via genre search.
            let effectiveThreshold = min(self.popularityThreshold + 25, 100)
            guard track.popularity < effectiveThreshold else {
                rejectionStats["too_popular"] = (rejectionStats["too_popular"] ?? 0) + 1
                return false 
            }
            
            // Filter 3: Not a compilation
            guard !isCompilationAlbum(track.album.name) else { 
                rejectionStats["compilation"] = (rejectionStats["compilation"] ?? 0) + 1
                return false 
            }
            
            // Filter 4: Language Check (Latin script only)
            guard isLatinScript(track.name) && isLatinScript(track.artists.first?.name ?? "") else {
                rejectionStats["non_latin_script"] = (rejectionStats["non_latin_script"] ?? 0) + 1
                return false
            }
            
            // Filter 5: Strict Spanish/Latin Language Filter
            if isLatinExcluded {
                if isLikelySpanish(track.name) || 
                   isLikelySpanish(track.artists.first?.name ?? "") || 
                   isLikelySpanish(track.album.name) {
                    rejectionStats["spanish_language"] = (rejectionStats["spanish_language"] ?? 0) + 1
                    return false
                }
            }
            
            // Filter 6: Name-Based Blacklist
            if let artistName = track.artists.first?.name, bannedArtistNames.contains(artistName) {
                rejectionStats["banned_artist"] = (rejectionStats["banned_artist"] ?? 0) + 1
                return false
            }
            
            return true
        }
        
        // Log rejection reasons
        if !rejectionStats.isEmpty {
            print("   📊 Rejection stats:")
            for (reason, count) in rejectionStats.sorted(by: { $0.value > $1.value }) {
                print("      - \(reason): \(count) tracks")
            }
        }
        print("   ✓ Pre-filtered to \(preFiltered.count) tracks. Checking artist details...")
        
        // 2. Batch check artist followers & genres (Optimized)
        var finalTracks: [SpotifyTrack] = []
        
        // Get unique artist IDs
        let artistIds = Set(preFiltered.compactMap { $0.artists.first?.id })
        let artistIdList = Array(artistIds)
        
        // Batch fetch artists (50 at a time) and store FULL objects
        var artistMap: [String: SpotifyArtist] = [:]
        
        for chunk in artistIdList.chunked(into: 50) {
            do {
                let artists = try await spotifyAPI.getArtists(ids: chunk, token: token)
                for artist in artists {
                    artistMap[artist.id] = artist
                }
                // Small delay to be nice to API
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            } catch {
                print("⚠️ Failed to fetch artist batch: \(error)")
            }
        }
        
        // 3. Final filter: Followers, Own Genres, and DEEP SCAN
        for track in preFiltered {
            guard let artistId = track.artists.first?.id else { continue }
            
            // Use cached artist details
            guard let artist = artistMap[artistId] else { continue }
            
            // Filter 6: Remix/Edit Hygiene (Avoid "techno remixes" of rock songs)
            // Filter 6: Remix/Edit Hygiene
            // Allow remixes ONLY if they are popular enough to be considered "significant"
            if strictMode {
                let lowerTitle = track.name.lowercased()
                if lowerTitle.contains("remix") || lowerTitle.contains(" mix") || lowerTitle.contains("edit") || lowerTitle.contains("version") {
                    // If it's a remix, it MUST meet the popularity threshold to show up
                    // (We assume popular remixes are higher quality/official)
                    if track.popularity < popularityThreshold {
                        print("   ❌ Strictly rejected '\(track.name)' (Low-quality Remix/Edit detected)")
                        continue
                    }
                }
            }

            // CHECK 1: Follower Count
            if let followers = artist.followers?.total {
                if followers >= followerThreshold {
                    continue
                }
            }
            
            // CHECK 2: Genre Validation (FULLY RELAXED - Fix #6)
            // We now FULLY TRUST Spotify's genre search results!
            // If a track came from genre:"folk" search, it's folk-adjacent enough.
            // Only reject if artist explicitly belongs to a HARD-BLACKLIST genre
            // (e.g., death metal artist accidentally appearing in folk results)
            if strictMode {
                if let genres = artist.genres, !genres.isEmpty {
                    // Only check for "hard blacklist" - extreme genres that NEVER belong
                    let hardBlacklist: Set<String> = ["death metal", "black metal", "grindcore", "screamo", "deathcore"]
                    let hasHardBlacklist = genres.contains { g in
                        hardBlacklist.contains { g.lowercased().contains($0) }
                    }
                    
                    if hasHardBlacklist {
                        print("   🔒 Hard Rejected \(artist.name): has blacklisted genre in \(genres)")
                        continue
                    }
                    // Otherwise, ALLOW - trust the genre search completely!
                }
                // Artists without genre tags are always allowed - they came from genre search
            }
            
            // CHECK 3: Blacklist Filtering (Only apply if NOT in selected genre families)
            // If user selected "Electronic", we shouldn't ban "trip hop" or "uk funky" (part of electronic family)
            if let genres = artist.genres, !genres.isEmpty {
                let hasExcludedGenre = genres.contains { artistGenre in
                    let lowerArtistGenre = artistGenre.lowercased()
                    
                    // Check if this genre belongs to any ALLOWED family (skip exclusion if it does)
                    let belongsToAllowedFamily = strictMode && allowedKeywords.contains { selectedGenre in
                        let family = genreFamilies[selectedGenre.lowercased()] ?? [selectedGenre.lowercased()]
                        return family.contains { familyGenre in
                            lowerArtistGenre.contains(familyGenre) || familyGenre.contains(lowerArtistGenre)
                        }
                    }
                    
                    // Only exclude if NOT in allowed family AND matches exclusion list
                    if belongsToAllowedFamily {
                        return false  // Don't exclude - it's part of selected genre family
                    }
                    
                    return excludedGenres.contains { excludedKeyword in
                        lowerArtistGenre.contains(excludedKeyword.lowercased())
                    }
                }
                
                if hasExcludedGenre {
                    let triggeringGenre = genres.first { g in
                        let lower = g.lowercased()
                        return excludedGenres.contains { k in lower.contains(k.lowercased()) }
                    } ?? "unknown"
                    print("   ❌ Strictly rejected \(artist.name) due to excluded genre: \(triggeringGenre)")
                    continue
                }
            }
            
            // CHECK 3 (removed): a "guilt by association" scan that rejected an
            // artist when their Spotify related-artists shared an excluded genre.
            // It relied on /artists/{id}/related-artists, which Spotify retired
            // in November 2024. The genre checks above cover the same ground.
            
            // If we passed all checks, keep the track
            finalTracks.append(track)
        }
        
        return finalTracks
    }
    
    // Original slow filter (kept for reference, not used)
    private func applyAllFilters(tracks: [SpotifyTrack], token: String) async throws -> [SpotifyTrack] {
        var filtered: [SpotifyTrack] = []
        
        for track in tracks {
            // Filter 1: Not already known
            guard !knownTrackIds.contains(track.id) else { continue }
            
            // Filter 2: Popularity < 30
            guard track.popularity < popularityThreshold else { continue }
            
            // Filter 3: Artist followers < 10k
            guard let artist = track.artists.first else { continue }
            
            // Fetch full artist details if needed
            var artistFollowers = artist.followers?.total
            if artistFollowers == nil {
                do {
                    let fullArtist = try await spotifyAPI.getArtistDetails(
                        artistId: artist.id,
                        token: token
                    )
                    artistFollowers = fullArtist.followers?.total
                } catch {
                    continue
                }
            }
            
            guard let followers = artistFollowers, followers < followerThreshold else {
                continue
            }
            
            // Filter 4: MusicBrainz validation (optional - commented out for performance)
            // Uncomment to enable strict compilation/remaster filtering
            /*
            do {
                let validation = try await musicBrainzService.validateGenuineRelease(
                    trackName: track.name,
                    artistName: artist.name
                )
                guard validation.isValid else { continue }
            } catch {
                // If MusicBrainz fails, still include the track
                print("⚠️ MusicBrainz validation failed: \(error)")
            }
            */
            
            // Filter 5: Not a compilation
            guard !isCompilationAlbum(track.album.name) else { continue }
            
            filtered.append(track)
        }
        
        return filtered
    }
    
    // MARK: - Scoring & Ranking
    
    // NEW: Score with AI explanations
    private func scoreAndRankWithExplanations(
        tracks: [SpotifyTrack],
        profile: ListeningProfile,
        vectorScores: [String: Double] = [:]
    ) -> [RecommendedTrack] {
        let allScored = tracks.map { track in
            let scores = calculateDetailedScores(track: track, profile: profile)
            
            // Weighted total score
            // If vector score exists, give it high weight (0.6)
            var totalScore = 0.0
            var matchScore = scores.tasteMatch
            
            if let vectorScore = vectorScores[track.id] {
                // Vector score is usually 0.7-0.9 for good matches
                totalScore = (vectorScore * 0.6) + (scores.obscurity * 0.2) + (scores.recency * 0.2)
                matchScore = vectorScore // Use vector score as the displayed match score
            } else {
                // Fallback to heuristic score
                totalScore = (scores.tasteMatch * 0.5) + (scores.obscurity * 0.3) + (scores.recency * 0.2)
            }
            
            let reason = generateObscurityReason(track: track, scores: scores)
            
            // Generate AI explanation
            let (explanation, similarTrack, reasons) = aiExplainer.generateExplanation(
                for: track,
                userLibrary: userLibrary,
                profile: profile
            )
            
            return RecommendedTrack(
                id: track.id,
                spotifyURI: track.uri,
                track: track,
                matchScore: scores.tasteMatch,
                obscurityScore: scores.obscurity,
                recencyScore: scores.recency,
                totalScore: totalScore,
                obscurityReason: reason,
                matchExplanation: explanation,
                similarToTrack: similarTrack,
                similarityReasons: reasons
            )
        }.sorted { $0.totalScore > $1.totalScore }
        
        // NEW: Deduplicate Artists (Keep only the best track per artist)
        var uniqueArtistTracks: [RecommendedTrack] = []
        var seenArtists = Set<String>()
        
        for track in allScored {
            guard let artistName = track.track.artists.first?.name else { continue }
            
            // Smart Deduplication: Check for similar artist names
            let isDuplicate = seenArtists.contains { existing in
                // Exact match
                if existing == artistName { return true }
                
                // Fuzzy match (Levenshtein distance)
                // Only check if lengths are close to avoid expensive calc
                if abs(existing.count - artistName.count) <= 2 {
                    let distance = levenshtein(existing.lowercased(), artistName.lowercased())
                    return distance <= 2 // Allow 2 character difference
                }
                
                return false
            }
            
            if !isDuplicate {
                uniqueArtistTracks.append(track)
                seenArtists.insert(artistName)
            }
        }
        
        return uniqueArtistTracks
    }
    
    // OLD: Keep for reference (not used)
    private func scoreAndRank(tracks: [SpotifyTrack], profile: ListeningProfile) -> [RecommendedTrack] {
        return tracks.map { track in
            let scores = calculateDetailedScores(track: track, profile: profile)
            
            // Weighted total score
            let totalScore = (scores.tasteMatch * 0.5) +
                           (scores.obscurity * 0.3) +
                           (scores.recency * 0.2)
            
            let reason = generateObscurityReason(track: track, scores: scores)
            
            return RecommendedTrack(
                id: track.id,
                spotifyURI: track.uri,
                track: track,
                matchScore: scores.tasteMatch,
                obscurityScore: scores.obscurity,
                recencyScore: scores.recency,
                totalScore: totalScore,
                obscurityReason: reason,
                matchExplanation: "",  // Empty for old version
                similarToTrack: nil,
                similarityReasons: []
            )
        }.sorted { $0.totalScore > $1.totalScore }
    }
    
    private func calculateDetailedScores(track: SpotifyTrack, profile: ListeningProfile) -> (tasteMatch: Double, obscurity: Double, recency: Double) {
        // Taste Match (genre + artist similarity)
        var tasteMatch = 0.0
        
        // Check genre overlap
        if let trackGenres = track.artists.first?.genres {
            let genreOverlap = trackGenres.filter { profile.genreWeights.keys.contains($0) }
            tasteMatch = Double(genreOverlap.count) / max(1.0, Double(trackGenres.count))
        }
        
        // Default moderate match if no genre data
        if tasteMatch == 0.0 {
            tasteMatch = 0.6
        }
        
        // Obscurity Score
        let popularityScore = (100.0 - Double(track.popularity)) / 100.0
        let followerScore = track.artists.first?.followers.flatMap { followers in
            (Double(followerThreshold) - Double(followers.total)) / Double(followerThreshold)
        } ?? 0.5
        let obscurity = (popularityScore + followerScore) / 2.0
        
        // Recency Score
        var recency = 0.5
        if let releaseDateString = track.album.releaseDate,
           let releaseDate = parseReleaseDate(releaseDateString) {
            let monthsAgo = Calendar.current.dateComponents([.month], from: releaseDate, to: Date()).month ?? recencyMonths
            recency = max(0.0, 1.0 - (Double(monthsAgo) / Double(recencyMonths)))
        }
        
        return (tasteMatch, obscurity, recency)
    }
    
    private func generateObscurityReason(track: SpotifyTrack, scores: (tasteMatch: Double, obscurity: Double, recency: Double)) -> String {
        var reasons: [String] = []
        
        if let followers = track.artists.first?.followers?.total {
            reasons.append("\(formatNumber(followers)) followers")
        }
        
        if track.popularity < 10 {
            reasons.append("ultra-rare")
        } else if track.popularity < 20 {
            reasons.append("very obscure")
        }
        
        if scores.recency > 0.8 {
            reasons.append("brand new")
        }
        
        return reasons.joined(separator: " • ")
    }
    
    // MARK: - Helpers
    
    private func updateProgress(_ message: String) async {
        await MainActor.run {
            self.discoveryProgress = message
        }
    }
    
    private func deduplicateTracks(_ tracks: [SpotifyTrack]) -> [SpotifyTrack] {
        var seen = Set<String>()
        return tracks.filter { track in
            if seen.contains(track.id) {
                return false
            }
            seen.insert(track.id)
            return true
        }
    }
    

    
    // MARK: - AI Vector Ranking
    
    private func rankByVectorSimilarity(tracks: [SpotifyTrack], tasteVector: [Double]) async throws -> [String: Double] {
        // Batch embed tracks
        let texts = tracks.map { track in
            "Track: \(track.name), Artist: \(track.artists.first?.name ?? "Unknown"), Album: \(track.album.name)"
        }
        
        let embeddings = try await openAIService.generateEmbeddings(texts: texts)
        
        var scores: [String: Double] = [:]
        
        for (index, embedding) in embeddings.enumerated() {
            guard index < tracks.count else { break }
            let trackId = tracks[index].id
            let similarity = cosineSimilarity(v1: tasteVector, v2: embedding)
            scores[trackId] = similarity
        }
        
        return scores
    }
    
    private func cosineSimilarity(v1: [Double], v2: [Double]) -> Double {
        guard v1.count == v2.count else { return 0.0 }
        
        let dotProduct = zip(v1, v2).map(*).reduce(0, +)
        let mag1 = sqrt(v1.map { $0 * $0 }.reduce(0, +))
        let mag2 = sqrt(v2.map { $0 * $0 }.reduce(0, +))
        
        guard mag1 > 0 && mag2 > 0 else { return 0.0 }
        return dotProduct / (mag1 * mag2)
    }
    
    private func parseReleaseDate(_ dateString: String) -> Date? {
        let formatters = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
    
    private func isCompilationAlbum(_ albumName: String) -> Bool {
        let keywords = ["best of", "greatest hits", "compilation", "collection", "essential"]
        let lower = albumName.lowercased()
        return keywords.contains(where: { lower.contains($0) })
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num < 1000 {
            return "\(num)"
        } else {
            return String(format: "%.1fK", Double(num) / 1000.0)
        }
    }
    
    // Levenshtein distance for fuzzy string matching
    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let s1Count = s1.count
        let s2Count = s2.count
        
        if s1Count == 0 { return s2Count }
        if s2Count == 0 { return s1Count }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count { matrix[i][0] = i }
        for j in 0...s2Count { matrix[0][j] = j }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                let s1Index = s1.index(s1.startIndex, offsetBy: i - 1)
                let s2Index = s2.index(s2.startIndex, offsetBy: j - 1)
                
                let cost = s1[s1Index] == s2[s2Index] ? 0 : 1
                
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[s1Count][s2Count]
    }
    
    // Helper to check if text is primarily Latin script (English, Spanish, French, etc.)
    // Returns false if it contains characters from other major scripts (CJK, Arabic, Cyrillic, etc.)
    private func isLatinScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            // Check for common non-Latin blocks
            let value = scalar.value
            
            // Hiragana (3040-309F) & Katakana (30A0-30FF)
            if (value >= 0x3040 && value <= 0x30FF) { return false }
            
            // CJK Unified Ideographs (4E00-9FFF)
            if (value >= 0x4E00 && value <= 0x9FFF) { return false }
            
            // Arabic (0600-06FF)
            if (value >= 0x0600 && value <= 0x06FF) { return false }
            
            // Cyrillic (0400-04FF)
            if (value >= 0x0400 && value <= 0x04FF) { return false }
            
            // Hebrew (0590-05FF)
            if (value >= 0x0590 && value <= 0x05FF) { return false }
            
            // Thai (0E00-0E7F)
            if (value >= 0x0E00 && value <= 0x0E7F) { return false }
            
            // Hangul (AC00-D7AF)
            if (value >= 0xAC00 && value <= 0xD7AF) { return false }
        }
        return true
    }
    
    // Helper to detect likely Spanish OR Portuguese text
    private func isLikelySpanish(_ text: String) -> Bool {
        let lower = text.lowercased()
        let words = lower.components(separatedBy: .punctuationCharacters).joined().components(separatedBy: .whitespaces)
        
        // 0. STRONG SINGLE-WORD INDICATORS (Reject on 1 match)
        // These are words that are almost exclusively Spanish/Portuguese and very common
        let strongIndicators: Set<String> = [
            // Spanish
            "estoy", "estás", "estas", "estamos", "estan", "están", // Be verb
            "soy", "eres", "somos", "son", // Be verb
            "tengo", "tienes", "tiene", "tenemos", "tienen", // Have verb
            "quiero", "quieres", "quiere", "queremos", "quieren", // Want verb
            "voy", "vas", "vamos", "van", // Go verb
            "corazón", "corazones", "canción", "canciones",
            "noche", "noches", "mujer", "mujeres", "hombre", "hombres",
            "vida", "muerte", "amor", "amar", "amado", "amada",
            "nuestro", "nuestra", "vuestro", "vuestra",
            "conmigo", "contigo", "consigo",
            "ahora", "siempre", "nunca", "jam&aacute;s", "jamas",
            "mañana", "ayer", "hoy",
            "verdad", "mentira", "sueño", "dolor",
            "feliz", "triste", "bailar", "fiesta",
            
            // Portuguese Specific
            "não", "nao", "são", "sao", "estão", "estao",
            "uma", "umas", "uns", // Articles
            "você", "voce", "vocês", "voces", // You
            "com", "sem", "pelo", "pela", "pelos", "pelas", // Prepositions
            "meu", "minha", "teu", "tua", "seu", "sua", // Possessives
            "agora", "depois", "onde", "quem", "tudó", "tudo",
            "muito", "muita", "bom", "boa", "bem"
        ]
        
        // Check strong indicators first
        for word in words {
            if strongIndicators.contains(word) {
                return true
            }
        }
        
        // 1. Common Stopwords (Require 2 matches for safety)
        let commonStopwords: Set<String> = [
            // Spanish
            "los", "las", "les", "nos",
            "pero", "porque", "aunque", 
            "del", "por", "para", "sobre", "entre", "hacia", "hasta",
            "quien", "quién", "cual", "cuál", 
            "mis", "tus", "sus", 
            "algo", "nada", "todo", "toda", "todos", "todas",
            "este", "esta", "esto", "ese", "esa", "eso",
            "mas", "más", "muy", "tan", "asi", "así",
            
            // Portuguese (Shared or unique)
            "os", "dos", "das", "aos",
            "em", "de", "da", "na",
            "que", "ou", "e", "é",
            "mais", "mas", "já", "ja",
            "ele", "ela", "eles", "elas", "nós", "nos"
        ]
        
        // 2. Music/Lyrical Keywords (Context) - Require 1 match if long enough
        let musicTerms: Set<String> = [
            // Genres/Styles
            "banda", "orquesta", "conjunto", "grupo", "trio", "trío", "sonora",
            "mariachi", "norteño", "norteña", "sierreño", "corrido", "corridos",
            "cumbia", "salsa", "merengue", "bachata", "reggaeton", "bolero",
            "ranchera", "flamenco", "trova", "vallenato", "huapango",
            "fado", "samba", "pagode", "bossa", "sertanejo", "forró", "forro",
            "axé", "axe", "frevo", "mpb",
            
            // Common Words (Shared SP/PT)
            "ritmo", "sabor", "calor", "sol", "lua", "luna",
            "cielo", "ceu", "céu", "mar", "mundo",
            "casa", "rua", "calle", "caminho", "camino",
            "fogo", "fuego", "vento", "viento",
            "flor", "flores", "rosa", "rosas",
            "reina", "rainha", "rei", "rey"
        ]
        
        var matchCount = 0
        for word in words {
            if commonStopwords.contains(word) || musicTerms.contains(word) {
                matchCount += 1
            }
            
            // Immediate return for explicit music terms > 3 chars
            if musicTerms.contains(word) && word.count > 3 {
                return true
            }
        }
        
        if matchCount >= 2 {
            return true
        }
        
        // 3. Suffix heuristics
        for word in words {
            if word.count > 4 {
                if word.hasSuffix("ción") || word.hasSuffix("cion") { return true } // Sp
                if word.hasSuffix("sión") || word.hasSuffix("sion") { return true } // Sp
                if word.hasSuffix("ção") || word.hasSuffix("cao") { return true }   // Pt
                if word.hasSuffix("são") || word.hasSuffix("sao") { return true }   // Pt
                if word.hasSuffix("dad") && !word.elementsEqual("dad") { return true } // Sp
                if word.hasSuffix("dade") { return true } // Pt
                if word.hasSuffix("mente") && !word.elementsEqual("cement") { return true } // Sp/Pt
            }
        }
        
        // 4. Special Characters
        let specialChars = ["ñ", "á", "é", "í", "ó", "ú", "ü", "¡", "¿", "ã", "õ", "à", "ç", "ê", "ô"]
        for char in specialChars {
            if lower.contains(char) { return true }
        }
        
        return false
    }

    // Helper to get all excluded genres (system + user)
    private func getExcludedGenres() -> [String] {
        let systemExcluded = [
            // Seasonal
            "christmas", "holiday", "halloween", "easter", "valentines",
            "new year", "thanksgiving", "hanukkah", "kwanzaa",
            // Children/Unwanted
            "children", "children's", "nursery", "lullaby", "disney",
            "soundtrack", "movie", "show tunes", "broadway", "musical",
            "anime", "game", "video game",
            // Religious/Specific
            "christian", "gospel", "worship", "islamic", "religious", "ccm",
            // Latin/Spanish
            "latin", "reggaeton", "spanish", "espanol", "musica", "tropical", "salsa", "bachata"
        ]
        
        var userExcluded: Set<String> = []
        if let data = UserDefaults.standard.data(forKey: "excludedGenres"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            userExcluded = decoded
        }
        
        return systemExcluded + Array(userExcluded)
    }
}

