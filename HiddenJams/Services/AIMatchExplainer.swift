//
//  AIMatchExplainer.swift
//  HiddenJams
//
//  Generates intelligent explanations for why a track matches user's taste
//  by comparing to specific tracks in their library
//

import Foundation

class AIMatchExplainer {
    
    // Find the best matching track from user's library and explain why
    func generateExplanation(
        for recommendedTrack: SpotifyTrack,
        userLibrary: [SpotifyTrack],
        profile: ListeningProfile
    ) -> (explanation: String, similarTrack: SpotifyTrack?, reasons: [String]) {
        
        // Find best match from user's library
        guard let bestMatch = findBestMatch(
            for: recommendedTrack,
            in: userLibrary
        ) else {
            // Fallback if no good match found
            return (
                "Matches your taste profile",
                nil,
                ["Fits your listening habits"]
            )
        }
        
        // Calculate similarity reasons
        let reasons = calculateSimilarityReasons(
            recommended: recommendedTrack,
            reference: bestMatch
        )
        
        // Generate natural language explanation
        // Generate natural language explanation
        let explanation = buildExplanation(
            recommended: recommendedTrack,
            reference: bestMatch,
            reasons: reasons,
            profile: profile
        )
        
        return (explanation, bestMatch, reasons)
    }
    
    // MARK: - Best Match Finding
    
    private func findBestMatch(
        for track: SpotifyTrack,
        in library: [SpotifyTrack]
    ) -> SpotifyTrack? {
        
        var bestScore: Double = 0.0
        var bestTrack: SpotifyTrack? = nil
        
        for libraryTrack in library {
            let score = calculateSimilarityScore(track, libraryTrack)
            
            if score > bestScore {
                bestScore = score
                bestTrack = libraryTrack
            }
        }
        
        // Lowered threshold to find more matches (was 0.3)
        return bestScore > 0.25 ? bestTrack : nil
    }
    
    private func calculateSimilarityScore(
        _ track1: SpotifyTrack,
        _ track2: SpotifyTrack
    ) -> Double {
        var score: Double = 0.0
        
        // Genre similarity (weight: 0.7) - most important without audio features
        if let genres1 = track1.artists.first?.genres,
           let genres2 = track2.artists.first?.genres {
            let overlap = Set(genres1).intersection(Set(genres2))
            if !overlap.isEmpty {
                let genreScore = Double(overlap.count) / Double(max(genres1.count, genres2.count, 1))
                score += genreScore * 0.7
            }
        }
        
        // Artist similarity (weight: 0.2)
        let artist1Ids = Set(track1.artists.map { $0.id })
        let artist2Ids = Set(track2.artists.map { $0.id })
        if !artist1Ids.intersection(artist2Ids).isEmpty {
            score += 0.2  // Same artist
        }
        
        // Popularity similarity (weight: 0.1) - similar vibe
        let popDiff = abs(Double(track1.popularity) - Double(track2.popularity))
        let popScore = max(0, 1.0 - (popDiff / 100.0))
        score += popScore * 0.1
        
        return score
    }
    
    // MARK: - Reason Generation
    
    private func calculateSimilarityReasons(
        recommended: SpotifyTrack,
        reference: SpotifyTrack
    ) -> [String] {
        var reasons: [String] = []
        
        // Genre match
        if let recGenres = recommended.artists.first?.genres,
           let refGenres = reference.artists.first?.genres {
            let overlap = Set(recGenres).intersection(Set(refGenres))
            if !overlap.isEmpty {
                let genre = overlap.first!.capitalized
                reasons.append("Same genre: \(genre)")
            }
        }
        
        // Artist match
        let recArtistIds = Set(recommended.artists.map { $0.id })
        let refArtistIds = Set(reference.artists.map { $0.id })
        if !recArtistIds.intersection(refArtistIds).isEmpty {
            if let artist = recommended.artists.first {
                reasons.append("Same artist: \(artist.name)")
            }
        }
        
        return reasons
    }
    
    // MARK: - Natural Language Generation
    
    private func buildExplanation(
        recommended: SpotifyTrack,
        reference: SpotifyTrack?,
        reasons: [String],
        profile: ListeningProfile
    ) -> String {
        // Priority 1: Direct Artist Match
        if let reference = reference,
           let refArtist = reference.artists.first?.name {
            return "Because you listen to \(refArtist)"
        }
        
        // Priority 2: Genre Match (Fallback)
        if let genre = recommended.artists.first?.genres?.first {
             return "Because you listen to \(genre.capitalized) music"
        }
        
        // Priority 3: Generic Fallback
        return "Because it matches your taste profile"
    }
    
    // MARK: - Helpers
    
    private func formatPopularity(_ popularity: Int) -> String {
        // Popularity is 0-100, rough estimate of listener count
        let estimated = (100 - popularity) * 1000
        if estimated < 5000 {
            return "< 5K"
        } else if estimated < 50000 {
            return "< 50K"
        } else {
            return "< 100K"
        }
    }
    
    private func getMonthsSinceRelease(_ dateString: String) -> Int? {
        let formatters = ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                let components = Calendar.current.dateComponents([.month], from: date, to: Date())
                return components.month
            }
        }
        
        return nil
    }
}
