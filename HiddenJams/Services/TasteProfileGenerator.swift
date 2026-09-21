//
//  TasteProfileGenerator.swift
//  HiddenJams
//
//  AI-powered taste profile generation from listening data
//

import Foundation

class TasteProfileGenerator {
    
    // MARK: - Personality Types
    
    static func generatePersonality(from profile: ListeningProfile) -> String {
        let audioFeatures = profile.audioFeatures
        let genres = profile.genreWeights.sorted { $0.value > $1.value }
        
        // Analyze characteristics to determine personality
        let isEnergetic = audioFeatures.energy > 0.7
        let isChill = audioFeatures.energy < 0.4 && audioFeatures.acousticness > 0.5
        let isDancer = audioFeatures.danceability > 0.7
        let isNostalgic = (profile.averageReleaseYear ?? 2020) < 2010
        let isEclectic = genres.count > 10
        let isInstrumental = audioFeatures.instrumentalness > 0.5
        let isValenced = audioFeatures.valence > 0.6
        
        // Determine personality based on traits
        if isInstrumental && isChill {
            return "🎧 The Focused Flow State"
        } else if isNostalgic && !isEnergetic {
            return "📼 The Vintage Soul"
        } else if isEclectic && genres.count > 15 {
            return "🌈 The Genre Wanderer"
        } else if isDancer && isValenced {
            return "💃 The Rhythm Chaser"
        } else if isEnergetic && !isDancer {
            return "⚡ The Electric Explorer"
        } else if isChill && isValenced {
            return "☀️ The Sunny Daydreamer"
        } else if !isEnergetic && !isValenced {
            return "🌙 The Midnight Listener"
        } else if isEclectic {
            return "🎨 The Eclectic Curator"
        } else {
            return "🎵 The Music Enthusiast"
        }
    }
    
    // MARK: - Profile Summary
    
    static func generateProfileSummary(from profile: ListeningProfile) -> String {
        let topGenres = profile.genreWeights.sorted { $0.value > $1.value }.prefix(3)
        let avgYear = profile.averageReleaseYear ?? 2020
        let decade = (avgYear / 10) * 10
        let audioFeatures = profile.audioFeatures
        
        // Build genre description
        var genreText = ""
        if topGenres.count > 0 {
            let genreNames = topGenres.map { formatGenreName($0.key) }
            if genreNames.count == 1 {
                genreText = genreNames[0]
            } else if genreNames.count == 2 {
                genreText = "\(genreNames[0]) and \(genreNames[1])"
            } else {
                genreText = "\(genreNames[0]), \(genreNames[1]), and \(genreNames[2])"
            }
        } else {
            genreText = "diverse music"
        }
        
        // Build era description
        let eraText: String
        if avgYear >= 2020 {
            eraText = "with a taste for the latest sounds"
        } else if avgYear >= 2010 {
            eraText = "grounded in the 2010s"
        } else if avgYear >= 2000 {
            eraText = "with strong 2000s vibes"
        } else if avgYear >= 1990 {
            eraText = "deeply rooted in the golden 90s"
        } else {
            eraText = "with a love for classic eras"
        }
        
        // Build energy description
        let energyText: String
        if audioFeatures.energy > 0.7 {
            energyText = "You crave high-energy tracks that keep you moving."
        } else if audioFeatures.energy < 0.4 {
            energyText = "You prefer laid-back, mellow vibes."
        } else {
            energyText = "You balance energetic and calm moments perfectly."
        }
        
        return "Your musical heart beats to \(genreText), \(eraText). \(energyText)"
    }
    
    // MARK: - Top Insights
    
    static func generateTopInsights(from profile: ListeningProfile) -> [String] {
        var insights: [String] = []
        
        // Decade insight
        if let avgYear = profile.averageReleaseYear {
            let decade = (avgYear / 10) * 10
            if avgYear < 2000 {
                insights.append("📼 \(Int((Double(profile.totalTracksAnalyzed) * 0.6)))+ tracks from the \(decade)s—you're vintage!")
            } else if avgYear < 2010 {
                insights.append("🎸 Strong \(decade)s energy in your library")
            } else if avgYear >= 2020 {
                insights.append("🆕 You're always on top of the latest releases")
            }
        }
        
        // Genre diversity insight
        if profile.genreWeights.count > 20 {
            insights.append("🌈 \(profile.genreWeights.count) different genres—you're a musical omnivore!")
        } else if profile.genreWeights.count > 10 {
            insights.append("🎨 \(profile.genreWeights.count) genres show your eclectic taste")
        }
        
        // Audio feature insights
        let features = profile.audioFeatures
        if features.danceability > 0.75 {
            insights.append("💃 \(Int(features.danceability * 100))% danceability—you NEED that groove")
        }
        
        if features.energy > 0.75 {
            insights.append("⚡ High-energy listener—you thrive on intensity")
        } else if features.energy < 0.35 {
            insights.append("🧘 Low energy preference—calm is your vibe")
        }
        
        if features.acousticness > 0.6 {
            insights.append("🎸 \(Int(features.acousticness * 100))% acoustic—you love organic sounds")
        }
        
        if features.valence > 0.65 {
            insights.append("😊 Happy music lover—positivity is your soundtrack")
        } else if features.valence < 0.35 {
            insights.append("🌙 You embrace melancholic beauty")
        }
        
        if features.instrumentalness > 0.4 {
            insights.append("🎼 Strong instrumental preference—lyrics optional")
        }
        
        // Artist loyalty insight
        if let topArtist = profile.topArtists.first {
            let percentage = Int(topArtist.influence * 100)
            insights.append("⭐ \(topArtist.name) is your #1 artist")
        }
        
        // Track count insight
        if profile.totalTracksAnalyzed > 1000 {
            insights.append("🎵 \(profile.totalTracksAnalyzed) tracks analyzed—deep library!")
        }
        
        // Return top 5 insights
        return Array(insights.prefix(5))
    }
    
    // MARK: - Top Genres Formatted
    
    static func generateTopGenresFormatted(from profile: ListeningProfile) -> [GenreItem] {
        let total = profile.genreWeights.values.reduce(0, +)
        guard total > 0 else { return [] }
        
        return profile.genreWeights
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { GenreItem(name: formatGenreName($0.key), percentage: $0.value / total) }
    }
    
    // MARK: - Mood Profile Calculation (FIX: Calculate from real audio features!)
    
    static func calculateMoodProfile(from audioFeatures: AudioFeatureProfile) -> MoodProfile {
        var mood = MoodProfile()
        
        // Happy: High valence + high energy
        mood.happy = ((audioFeatures.valence * 0.7) + (audioFeatures.energy * 0.3)).clamped(to: 0...1)
        
        // Sad: Low valence + low energy (inverted)
        mood.sad = ((1 - audioFeatures.valence) * 0.6 + (1 - audioFeatures.energy) * 0.4).clamped(to: 0...1)
        
        // Energetic: High energy
        mood.energetic = audioFeatures.energy
        
        // Calm: Low energy + high acousticness
        mood.calm = ((1 - audioFeatures.energy) * 0.5 + audioFeatures.acousticness * 0.5).clamped(to: 0...1)
        
        // Party: High danceability + high energy + high valence
        mood.party = ((audioFeatures.danceability * 0.5) + (audioFeatures.energy * 0.3) + (audioFeatures.valence * 0.2)).clamped(to: 0...1)
        
        // Focused: High instrumentalness + medium energy
        let focusEnergy = 1 - abs(audioFeatures.energy - 0.5) * 2  // Peaks at 0.5 energy
        mood.focused = ((audioFeatures.instrumentalness * 0.6) + (focusEnergy * 0.4)).clamped(to: 0...1)
        
        return mood
    }
    
    // MARK: - Obscurity Score
    
    static func calculateObscurityScore(from tracks: [SpotifyTrack]) -> Double {
        guard !tracks.isEmpty else { return 0 }
        
        let obscureTracks = tracks.filter { $0.popularity < 30 }
        let veryObscureTracks = tracks.filter { $0.popularity < 15 }
        
        // Weighted score: very obscure tracks count more
        let baseScore = Double(obscureTracks.count) / Double(tracks.count) * 100
        let bonusScore = Double(veryObscureTracks.count) / Double(tracks.count) * 20
        
        return min(baseScore + bonusScore, 100)
    }
    
    // MARK: - Tempo Category
    
    static func generateTempoCategory(from tempo: Double) -> String {
        switch tempo {
        case ..<80:
            return "🐢 Slow & Sultry (< 80 BPM)"
        case 80..<100:
            return "🌅 Chill Vibes (80-100 BPM)"
        case 100..<120:
            return "🚶 Steady Groove (100-120 BPM)"
        case 120..<140:
            return "🏃 Upbeat Energy (120-140 BPM)"
        case 140..<160:
            return "⚡ High Octane (140-160 BPM)"
        default:
            return "🚀 Hyperspeed (160+ BPM)"
        }
    }
    
    // MARK: - Fun Facts
    
    static func generateFunFacts(from profile: ListeningProfile, tracks: [SpotifyTrack]) -> [String] {
        var facts: [String] = []
        
        // Listening time estimate (avg 3.5 mins per track)
        let totalMinutes = profile.totalTracksAnalyzed * 4
        let hours = totalMinutes / 60
        let days = hours / 24
        if days > 0 {
            facts.append("⏱️ Your library is ~\(days) days of non-stop music")
        } else if hours > 0 {
            facts.append("⏱️ Your library is ~\(hours) hours of music")
        }
        
        // Obscurity percentile
        let obscurity = profile.obscurityScore
        if obscurity > 60 {
            facts.append("🎯 You're in the top 10% of obscure music hunters")
        } else if obscurity > 40 {
            facts.append("🔍 You dig deeper than 70% of listeners")
        } else if obscurity > 20 {
            facts.append("🎵 Nice mix of hits and underground tracks")
        }
        
        // Decade loyalty
        if let topDecade = profile.decadeDistribution.max(by: { $0.value < $1.value }) {
            let percentage = Int(Double(topDecade.value) / Double(max(profile.totalTracksAnalyzed, 1)) * 100)
            if percentage > 40 {
                facts.append("📅 \(percentage)% of your music is from the \(topDecade.key)")
            }
        }
        
        // Artist loyalty
        if let topArtist = profile.topArtists.first {
            let artistPercentage = Int(topArtist.influence * 100)
            if artistPercentage > 10 {
                facts.append("💜 \(topArtist.name) represents \(artistPercentage)% of your taste")
            }
        }
        
        // Genre diversity
        let genreCount = profile.genreWeights.count
        if genreCount > 30 {
            facts.append("🌈 \(genreCount) genres — you're a musical omnivore!")
        } else if genreCount > 15 {
            facts.append("🎨 \(genreCount) genres show your eclectic taste")
        }
        
        // Tempo fact
        let tempo = profile.audioFeatures.tempo
        if tempo > 140 {
            facts.append("💨 Your average BPM of \(Int(tempo)) means you like it FAST")
        } else if tempo < 90 {
            facts.append("🧘 \(Int(tempo)) BPM average — you prefer slow burns")
        }
        
        // Energy fact
        if profile.audioFeatures.energy > 0.75 {
            facts.append("⚡ \(Int(profile.audioFeatures.energy * 100))% average energy — you're electric!")
        } else if profile.audioFeatures.energy < 0.35 {
            facts.append("🌙 \(Int(profile.audioFeatures.energy * 100))% energy — chill is your middle name")
        }
        
        // Valence fact
        if profile.audioFeatures.valence > 0.7 {
            facts.append("☀️ Your music is \(Int(profile.audioFeatures.valence * 100))% positive vibes")
        } else if profile.audioFeatures.valence < 0.35 {
            facts.append("🖤 You embrace the melancholic side of music")
        }
        
        // Acoustic fact
        if profile.audioFeatures.acousticness > 0.6 {
            facts.append("🎸 \(Int(profile.audioFeatures.acousticness * 100))% acoustic — organic sounds for you")
        }
        
        return facts
    }
    
    // MARK: - Helpers
    
    private static func formatGenreName(_ genre: String) -> String {
        // Capitalize and clean up genre names for display
        return genre
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

