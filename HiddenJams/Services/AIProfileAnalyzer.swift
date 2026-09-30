//
//  AIProfileAnalyzer.swift
//  SpotifyHiddenGems
//
//  AI engine for analyzing the user's complete music library.
//
//  The analysis pipeline is source-agnostic: it works on [LibraryTrack], which
//  can come from Spotify, Apple Music, or both merged together. Source-specific
//  fetching happens in the entry points below; everything after that is shared.
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
    @Published var connectedSources: [MusicSource] = []
    /// Source-agnostic library (used as discovery seeds for Apple Music)
    @Published var libraryTracks: [LibraryTrack] = []

    private let apiService = SpotifyAPIService()
    private let appleMusicService: AppleMusicService
    private let openAIService = OpenAIService()

    init(appleMusicService: AppleMusicService) {
        self.appleMusicService = appleMusicService
    }

    // MARK: - Source-Specific Entry Points

    /// Analyze from Spotify (liked songs + top artists), as before.
    func analyzeCompleteLibrary(token: String) async {
        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
            errorMessage = nil
            currentStep = "Starting quick analysis..."
        }

        do {
            await MainActor.run {
                analysisProgress = 0.1
                currentStep = "Fetching your entire library..."
            }

            // Fetch all liked songs with progress updates
            let allTracks = try await apiService.getAllLikedTracks(token: token) { current, total in
                Task { @MainActor in
                    self.currentStep = "Fetching tracks: \(current)/\(total)"
                    let fetchProgress = Double(current) / Double(max(total, 1))
                    self.analysisProgress = 0.1 + (fetchProgress * 0.5)
                }
            }

            await MainActor.run {
                currentStep = "Analyzing your top artists..."
                analysisProgress = 0.5
            }

            let topArtists = try await apiService.getTopArtists(token: token, limit: 50)

            // Attach genre info from top artists to each track
            var artistGenres: [String: [String]] = [:]
            for artist in topArtists {
                artistGenres[artist.id] = artist.genres ?? []
            }
            let libraryTracks = allTracks.map { track -> LibraryTrack in
                let genres = track.artists.flatMap { artistGenres[$0.id] ?? [] }
                return LibraryTrack(from: track, genres: Array(Set(genres)))
            }

            print("✅ Fetched \(allTracks.count) tracks from Spotify Liked Songs")
            await analyze(libraryTracks: libraryTracks, spotifyToken: token, sources: [.spotify])

        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.currentStep = "Error: \(error.localizedDescription)"
                self.isAnalyzing = false
            }
        }
    }

    /// Analyze from the user's Apple Music library.
    func analyzeAppleMusicLibrary() async {
        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
            errorMessage = nil
            currentStep = "Reading your Apple Music library..."
            analysisProgress = 0.2
        }

        do {
            let tracks = try await appleMusicService.fetchLibraryTracks()
            guard !tracks.isEmpty else {
                throw AppleMusicError.fetchFailed("No songs found. Add music to your Apple Music library first.")
            }
            await analyze(libraryTracks: tracks, spotifyToken: nil, sources: [.appleMusic])
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.currentStep = "Error: \(error.localizedDescription)"
                self.isAnalyzing = false
            }
        }
    }

    /// Analyze from every connected source, merging and deduplicating.
    func analyzeAllConnectedSources(spotifyToken: String?) async {
        await MainActor.run {
            isAnalyzing = true
            analysisProgress = 0.0
            errorMessage = nil
            currentStep = "Fetching from all your music sources..."
            analysisProgress = 0.1
        }

        do {
            var libraries: [[LibraryTrack]] = []
            var sources: [MusicSource] = []

            // Fetch each source concurrently; one failing shouldn't kill the other
            await withTaskGroup(of: (MusicSource, [LibraryTrack]).self) { group in
                if let token = spotifyToken {
                    group.addTask {
                        do {
                            let tracks = try await self.apiService.getAllLikedTracks(token: token) { _, _ in }
                            let topArtists = try await self.apiService.getTopArtists(token: token, limit: 50)
                            var artistGenres: [String: [String]] = [:]
                            for artist in topArtists { artistGenres[artist.id] = artist.genres ?? [] }
                            let library = tracks.map { track -> LibraryTrack in
                                let genres = track.artists.flatMap { artistGenres[$0.id] ?? [] }
                                return LibraryTrack(from: track, genres: Array(Set(genres)))
                            }
                            return (.spotify, library)
                        } catch {
                            print("⚠️ Spotify library fetch failed: \(error)")
                            return (.spotify, [])
                        }
                    }
                }
                group.addTask {
                    do {
                        let tracks = try await self.appleMusicService.fetchLibraryTracks()
                        return (.appleMusic, tracks)
                    } catch {
                        print("⚠️ Apple Music library fetch failed: \(error)")
                        return (.appleMusic, [])
                    }
                }

                for await (source, tracks) in group {
                    if !tracks.isEmpty {
                        libraries.append(tracks)
                        sources.append(source)
                    }
                }
            }

            let merged = LibraryTrack.mergeDeduped(libraries.flatMap { $0 })
            guard !merged.isEmpty else {
                throw AppleMusicError.fetchFailed("Couldn't read any tracks from your connected sources.")
            }
            print("✅ Merged \(merged.count) unique tracks from \(sources.map { $0.displayName }.joined(separator: " + "))")
            await analyze(libraryTracks: merged, spotifyToken: spotifyToken, sources: sources)

        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.currentStep = "Error: \(error.localizedDescription)"
                self.isAnalyzing = false
            }
        }
    }

    // MARK: - Unified Analysis Pipeline

    /// The shared pipeline. Everything from here down is source-agnostic.
    private func analyze(libraryTracks: [LibraryTrack], spotifyToken: String?, sources: [MusicSource]) async {
        await MainActor.run {
            isAnalyzing = true
            errorMessage = nil
            currentStep = "Analyzing your top artists..."
            analysisProgress = 0.55
            self.connectedSources = sources
        }

        do {
            // Keep the SpotifyTrack-shaped copy for the discovery engine / explanations
            let spotifyShapedLibrary = libraryTracks.map { $0.toSpotifyTrack() }
            await MainActor.run {
                self.userLibraryTracks = spotifyShapedLibrary
                self.libraryTracks = libraryTracks
            }

            print("✅ Analyzing \(libraryTracks.count) tracks from \(sources.map { $0.displayName }.joined(separator: " + "))")

            await MainActor.run {
                currentStep = "Building your taste profile..."
                analysisProgress = 0.7
            }

            // Build profile (source-agnostic)
            let newProfile = buildProfile(tracks: libraryTracks)

            // Merge genre weights with any previously analyzed sources instead of
            // replacing them: connecting a second source (e.g. Apple Music after
            // Spotify) must ADD genres to the profile, never wipe the ones already
            // learned. The genre picker and discovery should only ever grow.
            let existingGenreWeights: [String: Double] = await MainActor.run { self.profile.genreWeights }
            let mergedGenreWeights = Self.mergedGenreWeights(existing: existingGenreWeights, new: newProfile.genreWeights)
            if mergedGenreWeights.count != newProfile.genreWeights.count {
                print("🎵 Genre merge: \(existingGenreWeights.count) existing + \(newProfile.genreWeights.count) new → \(mergedGenreWeights.count) total")
            }

            await MainActor.run {
                currentStep = "Generating personality..."
                analysisProgress = 0.9
            }

            // Generate taste profile
            var finalProfile = newProfile
            // Use the merged cross-source genre weights so personality text and the
            // genre picker reflect everything learned, not just this analysis run.
            finalProfile.genreWeights = mergedGenreWeights
            finalProfile.listeningPersonality = TasteProfileGenerator.generatePersonality(from: finalProfile)
            finalProfile.profileSummary = TasteProfileGenerator.generateProfileSummary(from: finalProfile)
            finalProfile.topInsights = TasteProfileGenerator.generateTopInsights(from: finalProfile)
            finalProfile.topGenresFormatted = TasteProfileGenerator.generateTopGenresFormatted(from: finalProfile)

            // Audio features are Spotify-only; skip gracefully otherwise
            await MainActor.run {
                currentStep = "Analyzing audio characteristics..."
                analysisProgress = 0.8
            }
            let audioProfile: AudioFeatureProfile
            if let token = spotifyToken {
                let spotifyTracks = libraryTracks.filter { $0.source == .spotify }
                let ids = Array(spotifyTracks.prefix(100).map { $0.id })
                audioProfile = await fetchAndCalculateAudioFeatures(trackIds: ids, token: token)
            } else {
                audioProfile = AudioFeatureProfile()
            }
            finalProfile.audioFeatures = audioProfile

            // Calculate REAL Mood Profile from audio features
            finalProfile.moodProfile = TasteProfileGenerator.calculateMoodProfile(from: audioProfile)
            print("✅ Calculated mood profile from audio features")

            // Fun stats
            finalProfile.obscurityScore = TasteProfileGenerator.calculateObscurityScore(from: spotifyShapedLibrary)
            finalProfile.tempoCategory = TasteProfileGenerator.generateTempoCategory(from: audioProfile.tempo)
            finalProfile.listeningMinutesEstimate = libraryTracks.count * 4  // ~4 min per track

            // Generate fun facts AFTER we have all the data
            finalProfile.funFacts = TasteProfileGenerator.generateFunFacts(from: finalProfile, tracks: spotifyShapedLibrary)
            print("✅ Generated \(finalProfile.funFacts.count) fun facts")

            // AI Analysis (Embeddings & LLM) — source-agnostic, uses names only
            await MainActor.run {
                currentStep = "Analyzing taste with AI..."
                analysisProgress = 0.95
            }

            if let vector = try? await generateTasteVector(tracks: libraryTracks) {
                finalProfile.tasteVector = vector
                print("✅ Generated Taste Vector (Dim: \(vector.count))")
            }

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
                print("   Tracks analyzed: \(libraryTracks.count)")
                print("   Obscurity score: \(Int(finalProfile.obscurityScore))%")

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

    private func buildProfile(tracks: [LibraryTrack]) -> ListeningProfile {
        var profile = ListeningProfile()

        profile.audioFeatures = AudioFeatureProfile() // Default neutral until updated

        // Build genre weights from per-track genre tags
        profile.genreWeights = calculateGenreWeights(tracks: tracks)

        // Create artist profiles from library frequency
        profile.topArtists = buildArtistProfiles(tracks: tracks)

        // Calculate decade distribution
        profile.decadeDistribution = calculateDecadeDistribution(tracks: tracks)
        profile.averageReleaseYear = calculateAverageReleaseYear(tracks: tracks)

        // Deprecated: Using default neutral mood
        profile.moodProfile = MoodProfile()

        // Metadata
        profile.totalTracksAnalyzed = tracks.count
        profile.lastAnalyzed = Date()
        profile.profileStrength = calculateProfileStrength(trackCount: tracks.count, artistCount: profile.topArtists.count)

        return profile
    }

    // MARK: - Audio Analysis

    private func fetchAndCalculateAudioFeatures(trackIds: [String], token: String) async -> AudioFeatureProfile {
        guard !trackIds.isEmpty else { return AudioFeatureProfile() }

        print("📊 Fetching audio features for \(trackIds.count) tracks...")

        let featuresList = try? await apiService.getAudioFeatures(trackIds: Array(trackIds.prefix(100)), token: token)
        guard let featuresList = featuresList, !featuresList.isEmpty else { return AudioFeatureProfile() }

        // Average them out
        var energy = 0.0
        var danceability = 0.0
        var valence = 0.0
        var acousticness = 0.0
        var instrumentalness = 0.0
        var tempo = 0.0
        var loudness = 0.0

        let count = Double(featuresList.count)

        for feature in featuresList {
            energy += feature.energy
            danceability += feature.danceability
            valence += feature.valence
            acousticness += feature.acousticness
            instrumentalness += feature.instrumentalness
            tempo += feature.tempo
            loudness += feature.loudness
        }

        print("✅ Calculated Audio Profile: Energy \(energy/count)")

        return AudioFeatureProfile(
            energy: energy / count,
            danceability: danceability / count,
            valence: valence / count,
            acousticness: acousticness / count,
            instrumentalness: instrumentalness / count,
            loudness: loudness / count,
            tempo: tempo / count
        )
    }

    // MARK: - Genre Analysis

    /// Merges genre weights from a fresh analysis into the weights learned from
    /// previously analyzed sources. The union only ever grows: connecting a new
    /// source (e.g. Apple Music after Spotify) adds its genres instead of
    /// wiping the ones already learned. Per-genre weight is the max seen.
    static func mergedGenreWeights(existing: [String: Double], new: [String: Double]) -> [String: Double] {
        var merged = existing
        for (genre, weight) in new {
            merged[genre] = max(merged[genre] ?? 0, weight)
        }
        return merged
    }

    private func calculateGenreWeights(tracks: [LibraryTrack]) -> [String: Double] {
        var genreCounts: [String: Int] = [:]
        var total = 0

        for track in tracks {
            for genre in track.genreNames {
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

    private func buildArtistProfiles(tracks: [LibraryTrack]) -> [ArtistProfile] {
        // Group tracks by artist
        var byArtist: [String: [LibraryTrack]] = [:]
        for track in tracks {
            byArtist[track.artistName, default: []].append(track)
        }

        let maxFrequency = byArtist.values.map { $0.count }.max() ?? 1

        var profiles: [ArtistProfile] = []
        for (artistName, artistTracks) in byArtist {
            let frequency = artistTracks.count
            let influence = Double(frequency) / Double(maxFrequency)
            // Union of genre tags across the artist's tracks
            let genres = Array(Set(artistTracks.flatMap { $0.genreNames }))
            // Stable ID: prefer the Spotify ID when the track came from Spotify
            let id = artistTracks.first(where: { $0.source == .spotify })?.id
                ?? "artist:\(artistName.lowercased())"

            profiles.append(ArtistProfile(
                id: id,
                name: artistName,
                genres: genres,
                frequency: frequency,
                influence: influence
            ))
        }

        return profiles.sorted { $0.influence > $1.influence }
    }

    // MARK: - Temporal Analysis

    private func calculateDecadeDistribution(tracks: [LibraryTrack]) -> [String: Int] {
        var distribution: [String: Int] = [:]

        for track in tracks {
            if let yearString = track.releaseDate?.prefix(4),
               let year = Int(yearString) {
                let decade = (year / 10) * 10
                let decadeKey = "\(decade)s"
                distribution[decadeKey, default: 0] += 1
            }
        }

        return distribution
    }

    private func calculateAverageReleaseYear(tracks: [LibraryTrack]) -> Int? {
        var years: [Int] = []

        for track in tracks {
            if let yearString = track.releaseDate?.prefix(4),
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
        // Persist the source-agnostic tracks too — Apple Music discovery seeds
        // from these, and without this the seeds were lost on every restart.
        UserDataManager.shared.saveSourceLibrary(libraryTracks)
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

        // Restore the source-agnostic library as well — Apple Music discovery
        // seeds from `libraryTracks`, which used to be empty after a restart
        // even when a cached profile existed (silent zero-result discovery).
        if let cachedSourceTracks = UserDataManager.shared.loadSourceLibrary() {
            self.libraryTracks = cachedSourceTracks
            print("✅ Loaded \(cachedSourceTracks.count) cached source library tracks")
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

    private func generateTasteVector(tracks: [LibraryTrack]) async throws -> [Double] {
        // Select top 50 most recent tracks + 50 random tracks to represent taste
        // (Embedding 3000 tracks is expensive and slow, 100 is a good sample)
        let recent = tracks.prefix(50)
        let random = tracks.dropFirst(50).shuffled().prefix(50)
        let sampleTracks = Array(recent) + Array(random)

        let texts = sampleTracks.map { track in
            "Track: \(track.title), Artist: \(track.artistName), Album: \(track.albumName)"
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
