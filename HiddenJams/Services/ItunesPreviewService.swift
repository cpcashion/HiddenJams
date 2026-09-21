//
//  ItunesPreviewService.swift
//  HiddenJams
//
//  Fallback service to fetch 30s previews from iTunes when Spotify fails
//

import Foundation

class ItunesPreviewService {
    private let baseURL = "https://itunes.apple.com/search"
    
    struct ItunesResponse: Codable {
        let resultCount: Int
        let results: [ItunesTrack]
    }
    
    struct ItunesTrack: Codable {
        let trackName: String
        let artistName: String
        let previewUrl: String?
        let trackViewUrl: String?
    }
    
    func findPreview(for trackName: String, artist: String) async -> String? {
        // Clean up query
        let cleanTrack = trackName.replacingOccurrences(of: " - Remastered", with: "")
                                .replacingOccurrences(of: " - Remaster", with: "")
                                .components(separatedBy: " (")[0] // Remove (feat. X) or (2011 Remaster)
        
        let query = "\(cleanTrack) \(artist)"
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "5")
        ]
        
        guard let url = components.url else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ItunesResponse.self, from: data)
            
            // Find best match
            if let match = response.results.first(where: { result in
                // Simple fuzzy match check
                let resultTrack = result.trackName.lowercased()
                let targetTrack = cleanTrack.lowercased()
                return resultTrack.contains(targetTrack) || targetTrack.contains(resultTrack)
            }) {
                return match.previewUrl
            }
            
            // Fallback to first result if strict match fails
            return response.results.first?.previewUrl
            
        } catch {
            print("⚠️ iTunes search failed for \(trackName): \(error.localizedDescription)")
            return nil
        }
    }
}
