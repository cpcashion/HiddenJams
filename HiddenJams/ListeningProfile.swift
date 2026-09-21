//
//  ListeningProfile.swift
//  SpotifyHiddenGems
//
//  AI-generated listening profile model
//

import Foundation

struct ListeningProfile: Codable {
    // Audio Feature Averages
    var audioFeatures: AudioFeatureProfile
    
    // Genre Preferences
    var genreWeights: [String: Double]
    
    // Artist Preferences
    var topArtists: [ArtistProfile]
    
    // Temporal Preferences
    var decadeDistribution: [String: Int]
    var averageReleaseYear: Int?
    
    // Mood Mapping
    var moodProfile: MoodProfile
    
    // Analysis Metadata
    var totalTracksAnalyzed: Int
    var lastAnalyzed: Date
    var profileStrength: Double // 0-1 confidence score
    
    // User-Facing Profile (NEW)
    var profileSummary: String?
    var listeningPersonality: String?
    var topInsights: [String]
    var topGenresFormatted: [GenreItem]
    
    // AI Taste Vector (Centroid)
    var tasteVector: [Double]?
    
    // NEW: Fun Stats
    var obscurityScore: Double  // 0-100, how obscure is user's taste
    var tempoCategory: String?  // "Chill (80-100 BPM)" etc.
    var funFacts: [String]      // Unique, personalized facts
    var listeningMinutesEstimate: Int  // Estimated minutes of music
    
    init() {
        self.audioFeatures = AudioFeatureProfile()
        self.genreWeights = [:]
        self.topArtists = []
        self.decadeDistribution = [:]
        self.moodProfile = MoodProfile()
        self.totalTracksAnalyzed = 0
        self.lastAnalyzed = Date()
        self.profileStrength = 0.0
        self.profileSummary = nil
        self.listeningPersonality = nil
        self.topInsights = []
        self.topGenresFormatted = []
        self.tasteVector = nil
        self.obscurityScore = 0.0
        self.tempoCategory = nil
        self.funFacts = []
        self.listeningMinutesEstimate = 0
    }
    
    enum CodingKeys: String, CodingKey {
        case audioFeatures, genreWeights, topArtists
        case decadeDistribution, averageReleaseYear, moodProfile
        case totalTracksAnalyzed, lastAnalyzed, profileStrength
        case profileSummary, listeningPersonality, topInsights, topGenresFormatted
        case tasteVector, obscurityScore, tempoCategory, funFacts, listeningMinutesEstimate
    }
}

// MARK: - Audio Feature Profile
struct AudioFeatureProfile: Codable {
    var acousticness: Double
    var danceability: Double
    var energy: Double
    var instrumentalness: Double
    var liveness: Double
    var speechiness: Double
    var valence: Double
    var tempo: Double
    var loudness: Double
    
    /// Whether these numbers came from real data.
    ///
    /// Spotify withdrew `/audio-features` in November 2024, so on current
    /// builds nothing populates these fields and they hold placeholder
    /// midpoints. Optional (rather than a plain `Bool`) so profiles persisted
    /// by older versions still decode — a missing key reads as nil.
    var featuresAvailable: Bool?

    /// True only when the values reflect real measurements. The UI should hide
    /// audio-feature dimensions when this is false rather than present 0.5s as
    /// though they meant something.
    var isAvailable: Bool { featuresAvailable ?? false }

    // Ranges for variability
    var acousticnessRange: ClosedRange<Double>?
    var danceabilityRange: ClosedRange<Double>?
    var energyRange: ClosedRange<Double>?
    var tempoRange: ClosedRange<Double>?
    
    init() {
        self.acousticness = 0.5
        self.danceability = 0.5
        self.energy = 0.5
        self.instrumentalness = 0.5
        self.liveness = 0.5
        self.speechiness = 0.5
        self.valence = 0.5
        self.tempo = 120.0
        self.loudness = -5.0
        self.featuresAvailable = false
    }
    
    init(energy: Double, danceability: Double, valence: Double, acousticness: Double, instrumentalness: Double, loudness: Double, tempo: Double) {
        self.energy = energy
        self.danceability = danceability
        self.valence = valence
        self.acousticness = acousticness
        self.instrumentalness = instrumentalness
        self.loudness = loudness
        self.tempo = tempo
        
        self.liveness = 0.5
        self.speechiness = 0.5
        self.featuresAvailable = true
        self.acousticnessRange = nil
        self.danceabilityRange = nil
        self.energyRange = nil
        self.tempoRange = nil
    }
    
    enum CodingKeys: String, CodingKey {
        case acousticness, danceability, energy, instrumentalness
        case liveness, speechiness, valence, tempo, loudness
        case featuresAvailable
    }
}

// MARK: - Artist Profile
struct ArtistProfile: Codable, Identifiable {
    let id: String
    let name: String
    let genres: [String]
    let frequency: Int // How many times they appear in user's library
    let influence: Double // 0-1 score
}

// MARK: - Mood Profile
struct MoodProfile: Codable {
    var happy: Double // High valence, high energy
    var sad: Double // Low valence, low energy
    var energetic: Double // High energy
    var calm: Double // Low energy, high acousticness
    var party: Double // High danceability, high energy
    var focused: Double // High instrumentalness, medium energy
    
    init() {
        self.happy = 0.5
        self.sad = 0.5
        self.energetic = 0.5
        self.calm = 0.5
        self.party = 0.5
        self.focused = 0.5
    }
}

// MARK: - Hidden Gem
struct HiddenGem: Identifiable, Codable {
    let id: String
    let track: SpotifyTrack
    let matchScore: Double // 0-100 AI similarity score
    let matchReasons: [String] // Why this matches user's taste
    let streamCount: Int? // Actual stream count if available
    let popularity: Int
    
    var isHiddenGem: Bool {
        if let streams = streamCount {
            return streams < 1000
        }
        return popularity < 20
    }
}

// MARK: - Genre Item
struct GenreItem: Codable, Hashable {
    let name: String
    let percentage: Double
}
