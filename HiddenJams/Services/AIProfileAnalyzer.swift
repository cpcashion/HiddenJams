//
//  AIProfileAnalyzer.swift
//  SpotifyHiddenGems
//
//  AI engine for analyzing user's complete music library
//

import Foundation
import Combine

class AIProfileAnalyzer: ObservableObject {
    @Published var profile: ListeningProfile = ListeningProfile()
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    @Published var currentStep: String = ""
    @Published var errorMessage: String?
    @Published var userLibraryTracks: [SpotifyTrack] = []  // Store for AI explanations
    
    private let apiService = SpotifyAPIService()
    private let openAIService = OpenAIService()
    
    // MARK: - Main Analysis Pipeline
    
    func analyzeCompleteLibrary(token: String) async {
        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
            errorMessage = nil
            currentStep = "Starting quick analysis..."
        }
        
        do {
            // Step 1: Get ALL Liked Songs (Complete Library)
            await MainActor.run {
                analysisProgress = 0.1
                currentStep = "Fetching your entire library..."
            }
            
            // Fetch all liked songs with progress updates
            let allTracks = try await apiService.getAllLikedTracks(token: token) { current, total in
                Task { @MainActor in
                    self.currentStep = "Fetching tracks: \(current)/\(total)"
                    // Map progress 0.1 -> 0.6 based on fetch progress
                    let fetchProgress = Double(current) / Double(max(total, 1))
                    self.analysisProgress = 0.1 + (fetchProgress * 0.5)
                }
            }
            
            // Store for AI explanations
            await MainActor.run {
                self.userLibraryTracks = allTracks
            }
            
            print("✅ Fetched \(allTracks.count) tracks from Liked Songs")
            print("📊 Analysis source: Complete Library")
            
            await MainActor.run {
                currentStep = "Analyzing your top artists..."
                analysisProgress = 0.5
            }
            
            // Step 2: Get top artists
            let topArtists = try await apiService.getTopArtists(token: token, limit: 50)
            
            await MainActor.run {
                currentStep = "Building your taste profile..."
                analysisProgress = 0.7
            }
            
            // Step 3: Build profile
            let newProfile = buildProfile(
                tracks: allTracks,
                topArtists: topArtists
            )
            
            await MainActor.run {
                currentStep = "Generating personality..."
                analysisProgress = 0.9
            }
            
            // Step 4: Generate taste profile
            var finalProfile = newProfile
            finalProfile.listeningPersonality = TasteProfileGenerator.generatePersonality(from: newProfile)
            finalProfile.profileSummary = TasteProfileGenerator.generateProfileSummary(from: newProfile)
            finalProfile.topInsights = TasteProfileGenerator.generateTopInsights(from: newProfile)
            finalProfile.topGenresFormatted = TasteProfileGenerator.generateTopGenresFormatted(from: newProfile)
            
            // Step 4.5: Calculate REAL Audio Features
            await MainActor.run {
                currentStep = "Analyzing audio characteristics..."
                analysisProgress = 0.8
            }
            let audioProfile = await fetchAndCalculateAudioFeatures(for: allTracks, token: token)
            finalProfile.audioFeatures = audioProfile
            
            // Step 4.6: Calculate REAL Mood Profile from audio features (FIX!)
            finalProfile.moodProfile = TasteProfileGenerator.calculateMoodProfile(from: audioProfile)
            print("✅ Calculated mood profile from real audio features")
            
            // Step 4.7: Calculate fun stats
            finalProfile.obscurityScore = TasteProfileGenerator.calculateObscurityScore(from: allTracks)
            finalProfile.tempoCategory = TasteProfileGenerator.generateTempoCategory(from: audioProfile.tempo)
            finalProfile.listeningMinutesEstimate = allTracks.count * 4  // ~4 min per track
            
            // Generate fun facts AFTER we have all the data
            finalProfile.funFacts = TasteProfileGenerator.generateFunFacts(from: finalProfile, tracks: allTracks)
            print("✅ Generated \(finalProfile.funFacts.count) fun facts")
            
            // Step 5: AI Analysis (Embeddings & LLM)
            await MainActor.run {
                currentStep = "Analyzing taste with AI..."
                analysisProgress = 0.95
            }
            
            // Generate Taste Vector
            if let vector = try? await generateTasteVector(tracks: allTracks) {
                finalProfile.tasteVector = vector
                print("✅ Generated Taste Vector (Dim: \(vector.count))")
            }
            
            // Generate LLM Personality
            if let aiPersonality = try? await generateAIPersonality(profile: finalProfile) {
                finalProfile.listeningPersonality = "✨ AI Analysis"
                finalProfile.profileSummary = aiPersonality
                print("✅ Generated AI Personality")
            }
            
            await MainActor.run {
                self.profile = finalProfile
                self.analysisProgress = 1.0
                self.currentStep = "Complete! ✨"
                self.isAnalyzing = false
                
                print("✅ Profile generated:")
                print("   Personality: \(finalProfile.listeningPersonality ?? "Unknown")")
                print("   Summary: \(finalProfile.profileSummary ?? "No summary")")
                print("   Tracks analyzed: \(allTracks.count)")
                print("   Artists analyzed: \(topArtists.count)")
                print("   Obscurity score: \(Int(finalProfile.obscurityScore))%")
                print("   Mood - Happy: \(Int(finalProfile.moodProfile.happy * 100))%")
                
                // Save profile and library
                self.saveProfile()
                self.saveUserLibrary()
            }
            
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.currentStep = "Error: \(error.localizedDescription)"
                self.isAnalyzing = false
            }
        }
    }
    
    // MARK: - Profile Building
    
    private func buildProfile(
        tracks: [SpotifyTrack],
        topArtists: [SpotifyArtist]
    ) -> ListeningProfile {
        var profile = ListeningProfile()
        
        // Calculate average audio features
        // Fetch real features concurrently later, but initially set defaults or estimate if available
        // Since we are inside non-async scope, we set defaults here and update later in parallel
        profile.audioFeatures = AudioFeatureProfile() // Default neutral until updated
        
        // Build genre weights from top artists
        profile.genreWeights = calculateGenreWeights(topArtists: topArtists)
        
        // Create artist profiles
        profile.topArtists = buildArtistProfiles(tracks: tracks, topArtists: topArtists)
        
        // Calculate decade distribution
        profile.decadeDistribution = calculateDecadeDistribution(tracks: tracks)
        profile.averageReleaseYear = calculateAverageReleaseYear(tracks: tracks)
        
        // Build mood profile
        // Deprecated: Using default neutral mood
        profile.moodProfile = MoodProfile()
        
        // Metadata
        profile.totalTracksAnalyzed = tracks.count
        profile.lastAnalyzed = Date()
        profile.profileStrength = calculateProfileStrength(trackCount: tracks.count, artistCount: topArtists.count)
        
        return profile
    }
    
    // MARK: - Audio Analysis
    
    /// Audio features are no longer available from Spotify.
    ///
    /// The `/audio-features` endpoint (energy, danceability, valence, tempo…)
    /// was withdrawn on 27 November 2024 for apps without prior extended
    /// access, and there is no replacement in the Web API. It previously
    /// failed inside a `do/catch` here, which meant profiles quietly came back
    /// with every value at zero and nothing indicated why.
    ///
    /// Taste profiling now runs on genre and artist signals, which are still
    /// fully available. `AudioFeatureProfile.isAvailable` lets the UI hide
    /// these dimensions rather than render a row of zeroes.
    private func fetchAndCalculateAudioFeatures(for tracks: [SpotifyTrack], token: String) async -> AudioFeatureProfile {
        return AudioFeatureProfile()
    }
    

    
    // MARK: - Genre Analysis
    
    private func calculateGenreWeights(topArtists: [SpotifyArtist]) -> [String: Double] {
        var genreCounts: [String: Int] = [:]
        var total = 0
        
        for artist in topArtists {
            for genre in artist.genres ?? [] {
                genreCounts[genre, default: 0] += 1
                total += 1
            }
        }
        
        // Convert to weights (0-1)
        var weights: [String: Double] = [:]
        for (genre, count) in genreCounts {
            weights[genre] = Double(count) / Double(max(total, 1))
        }
        
        return weights
    }
    
    // MARK: - Artist Profiles
    
    private func buildArtistProfiles(tracks: [SpotifyTrack], topArtists: [SpotifyArtist]) -> [ArtistProfile] {
        var artistFrequency: [String: Int] = [:]
        
        // Count artist appearances in tracks
        for track in tracks {
            for artist in track.artists {
                artistFrequency[artist.id, default: 0] += 1
            }
        }
        
        // Build profiles from top artists
        var profiles: [ArtistProfile] = []
        let maxFrequency = artistFrequency.values.max() ?? 1
        
        for artist in topArtists.prefix(20) {
            let frequency = artistFrequency[artist.id] ?? 0
            let influence = Double(frequency) / Double(maxFrequency)
            
            let profile = ArtistProfile(
                id: artist.id,
                name: artist.name,
                genres: artist.genres ?? [],
                frequency: frequency,
                influence: influence
            )
            profiles.append(profile)
        }
        
        return profiles.sorted { $0.influence > $1.influence }
    }
    
    // MARK: - Temporal Analysis
    
    private func calculateDecadeDistribution(tracks: [SpotifyTrack]) -> [String: Int] {
        var distribution: [String: Int] = [:]
        
        for track in tracks {
            if let yearString = track.album.releaseDate?.prefix(4),
               let year = Int(yearString) {
                let decade = (year / 10) * 10
                let decadeKey = "\(decade)s"
                distribution[decadeKey, default: 0] += 1
            }
        }
        
        return distribution
    }
    
    private func calculateAverageReleaseYear(tracks: [SpotifyTrack]) -> Int? {
        var years: [Int] = []
        
        for track in tracks {
            if let yearString = track.album.releaseDate?.prefix(4),
               let year = Int(yearString) {
                years.append(year)
            }
        }
        
        guard !years.isEmpty else { return nil }
        return years.reduce(0, +) / years.count
    }
    

    
    // MARK: - Profile Strength
    
    private func calculateProfileStrength(trackCount: Int, artistCount: Int) -> Double {
        // Profile strength based on data quantity
        let trackScore = min(Double(trackCount) / 500.0, 1.0) * 0.7
        let artistScore = min(Double(artistCount) / 50.0, 1.0) * 0.3
        
        return trackScore + artistScore
    }
    
    // MARK: - Persistence
    
    private func saveProfile() {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "listening_profile")
        }
    }
    
    private func saveUserLibrary() {
        UserDataManager.shared.saveUserLibrary(userLibraryTracks)
    }
    
    func loadProfile() {
        if let data = UserDefaults.standard.data(forKey: "listening_profile"),
           let decoded = try? JSONDecoder().decode(ListeningProfile.self, from: data) {
            self.profile = decoded
            print("✅ Loaded cached profile with \(decoded.totalTracksAnalyzed) tracks")
        }
        
        // Also load cached library tracks for AI explanations
        if let cachedTracks = UserDataManager.shared.loadUserLibrary() {
            self.userLibraryTracks = cachedTracks
            print("✅ Loaded \(cachedTracks.count) cached library tracks")
        }
    }
    
    /// Check if a valid analyzed profile exists that can skip re-analysis
    var hasValidProfile: Bool {
        return profile.totalTracksAnalyzed > 0 && !userLibraryTracks.isEmpty
    }
    
    /// Number of days since last analysis
    var daysSinceLastAnalysis: Int? {
        UserDataManager.shared.daysSinceLastAnalysis
    }
    
    // MARK: - AI Helpers
    
    private func generateTasteVector(tracks: [SpotifyTrack]) async throws -> [Double] {
        // Select top 50 most recent tracks + 50 random tracks to represent taste
        // (Embedding 3000 tracks is expensive and slow, 100 is a good sample)
        let recent = tracks.prefix(50)
        let random = tracks.dropFirst(50).shuffled().prefix(50)
        let sampleTracks = Array(recent) + Array(random)
        
        let texts = sampleTracks.map { track in
            "Track: \(track.name), Artist: \(track.artists.first?.name ?? "Unknown"), Album: \(track.album.name)"
        }
        
        let embeddings = try await openAIService.generateEmbeddings(texts: texts)
        
        // Calculate Centroid (Average)
        guard !embeddings.isEmpty else { return [] }
        let dimensions = embeddings[0].count
        var centroid = Array(repeating: 0.0, count: dimensions)
        
        for embedding in embeddings {
            for i in 0..<dimensions {
                centroid[i] += embedding[i]
            }
        }
        
        return centroid.map { $0 / Double(embeddings.count) }
    }
    
    private func generateAIPersonality(profile: ListeningProfile) async throws -> String {
        // Construct stats string
        let topGenres = profile.topGenresFormatted.prefix(5).map { $0.name }.joined(separator: ", ")
        let topArtists = profile.topArtists.prefix(5).map { $0.name }.joined(separator: ", ")
        let decades = profile.decadeDistribution.sorted { $0.value > $1.value }.prefix(3).map { $0.key }.joined(separator: ", ")
        
        let stats = """
        Top Genres: \(topGenres)
        Top Artists: \(topArtists)
        Top Decades: \(decades)
        Total Tracks: \(profile.totalTracksAnalyzed)
        """
        
        return try await openAIService.generateTasteProfile(stats: stats)
    }
}
