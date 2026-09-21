//
//  EveryNoiseService.swift
//  HiddenJams
//
//  Service for discovering micro-genres and niche artists using Every Noise at Once data
//

import Foundation

class EveryNoiseService {
    // Every Noise at Once genre data (simplified for now)
    // In production, this could be fetched from their website or a cached JSON file
    
    private let genreMapping: [String: [String]] = [
        "indie": ["bedroom pop", "lo-fi indie", "indie folk", "chamber pop", "slowcore", "shoegaze"],
        "rock": ["math rock", "post-rock", "noise rock", "psychedelic rock", "garage rock", "art rock", "stoner rock"],
        "electronic": ["vaporwave", "future bass", "witch house", "hypnagogic pop", "chillwave", "drum and bass", "liquid funk", "neurofunk"],
        "pop": ["hyperpop", "art pop", "synthpop", "dream pop", "indie pop"],
        "hip hop": ["abstract hip hop", "cloud rap", "experimental hip hop", "lo-fi hip hop"],
        "folk": ["freak folk", "anti-folk", "neofolk", "chamber folk", "indie folk", 
                 "psych folk", "new weird america", "singer-songwriter", "stomp and holler",
                 "contemporary folk", "traditional folk", "acoustic", "americana", "roots"],
        "jazz": ["spiritual jazz", "nu jazz", "free jazz", "jazz fusion", "avant-garde jazz"],
        "metal": ["atmospheric black metal", "post-metal", "doom metal", "sludge metal"],
        "r&b": ["alternative r&b", "neo soul", "bedroom r&b", "indie r&b"],
        // DnB-specific micro-genres for deep discovery
        "drum and bass": ["liquid funk", "neurofunk", "jump up", "darkstep", "intelligent dnb", "halftime", "liquid dnb", "techstep", "atmospheric dnb", "minimal dnb"],
        "drum-and-bass": ["liquid funk", "neurofunk", "jump up", "darkstep", "intelligent dnb", "halftime", "liquid dnb", "techstep", "atmospheric dnb", "minimal dnb"],
        "jungle": ["ragga jungle", "darkside jungle", "intelligent jungle", "old school jungle"],
        // NEW: Additional common genres that were missing
        "alternative": ["indie rock", "post-punk", "art rock", "shoegaze", "dream pop", 
                        "noise pop", "slowcore", "lo-fi", "new wave", "college rock",
                        "britpop", "grunge", "alternative metal", "gothic rock", "emo"],
        "ambient": ["dark ambient", "drone", "space music", "new age", "meditation", "atmospheric"],
        "soul": ["neo soul", "northern soul", "southern soul", "psychedelic soul", "blue-eyed soul"],
        "funk": ["p-funk", "electro funk", "synth funk", "acid funk", "go-go"],
        "punk": ["post-punk", "hardcore punk", "pop punk", "anarcho-punk", "street punk", "skate punk"],
        "country": ["alt-country", "outlaw country", "americana", "country rock", "honky tonk", "bluegrass"],
        "reggae": ["dub", "roots reggae", "dancehall", "rocksteady", "lovers rock", "ragga"],
        "blues": ["delta blues", "chicago blues", "electric blues", "blues rock", "modern blues"],
        "classical": ["contemporary classical", "minimalism", "neo-classical", "avant-garde classical", "chamber music"]
    ]
    
    // MARK: - Micro-Genre Discovery
    
    /// Get micro-genres related to a broad genre
    /// - Parameter genre: Broad genre name (e.g., "indie", "rock")
    /// - Returns: Array of related micro-genre names
    func getMicroGenres(fromGenre genre: String) -> [String] {
        let normalizedGenre = genre.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for exact match
        if let microGenres = genreMapping[normalizedGenre] {
            print("🎵 Found \(microGenres.count) micro-genres for '\(genre)'")
            return microGenres
        }
        
        // Check for partial matches
        let partialMatches = genreMapping.filter { key, _ in
            normalizedGenre.contains(key) || key.contains(normalizedGenre)
        }
        
        let allMicroGenres = partialMatches.flatMap { $0.value }
        
        if !allMicroGenres.isEmpty {
            print("🎵 Found \(allMicroGenres.count) micro-genres related to '\(genre)'")
        }
        
        return Array(Set(allMicroGenres)) // Remove duplicates
    }
    
    /// Get micro-genres from multiple broad genres
    /// - Parameter genres: Array of broad genre names
    /// - Returns: Combined array of micro-genres
    func getMicroGenres(fromGenres genres: [String]) -> [String] {
        let allMicroGenres = genres.flatMap { getMicroGenres(fromGenre: $0) }
        return Array(Set(allMicroGenres)) // Remove duplicates
    }
    
    /// Expand a user's genre preferences into niche micro-genres
    /// - Parameter userGenres: User's favorite genres from taste profile
    /// - Returns: Expanded list of micro-genres to explore
    func expandGenres(_ userGenres: [String]) -> [String] {
        var expanded: [String] = []
        
        for genre in userGenres {
            // Add the original genre
            expanded.append(genre)
            
            // Add micro-genres
            let microGenres = getMicroGenres(fromGenre: genre)
            expanded.append(contentsOf: microGenres)
        }
        
        return Array(Set(expanded)).sorted()
    }
    
    // MARK: - Genre Similarity
    
    /// Find similar genres based on mapping
    /// - Parameter genre: Source genre
    /// - Returns: Array of similar genre names
    func getSimilarGenres(_ genre: String) -> [String] {
        let normalizedGenre = genre.lowercased()
        
        // If it's a broad genre, return its micro-genres
        if let microGenres = genreMapping[normalizedGenre] {
            return microGenres
        }
        
        // If it's a micro-genre, find other micro-genres in the same family
        for (broadGenre, microGenres) in genreMapping {
            if microGenres.contains(where: { $0.lowercased() == normalizedGenre }) {
                // Return other micro-genres in the same family
                return microGenres.filter { $0.lowercased() != normalizedGenre }
            }
        }
        
        return []
    }
}

// MARK: - Future Enhancement Ideas

/*
 Future improvements for this service:
 
 1. Fetch live data from Every Noise at Once website
    - Scrape https://everynoise.com/engenremap.html
    - Parse genre positions and relationships
 
 2. Genre similarity scoring
    - Use genre positioning data to calculate similarity
    - Weight by proximity in the genre space
 
 3. Artist discovery by genre
    - Fetch artist lists for each micro-genre
    - Cross-reference with Spotify follower counts
 
 4. Cache genre data locally
    - Store in JSON file for offline access
    - Update periodically from source
 
 5. Dynamic genre learning
    - Learn user's micro-genre preferences over time
    - Suggest increasingly niche genres based on likes
 */
