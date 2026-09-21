//
//  DeezerPreviewService.swift
//  HiddenJams
//
//  Fallback preview source using Deezer's free API
//

import Foundation

class DeezerPreviewService {
    
    /// Search Deezer for a track and return its 30-second preview URL if available
    func findPreview(for trackName: String, artist: String) async -> String? {
        // Clean up the search query
        let cleanTrack = trackName
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " - ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        
        let cleanArtist = artist
            .replacingOccurrences(of: "&", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let query = "\(cleanArtist) \(cleanTrack)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "https://api.deezer.com/search?q=\(query)&limit=5") else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            
            let result = try JSONDecoder().decode(DeezerSearchResponse.self, from: data)
            
            // Find best match - look for artist name match
            let artistLower = artist.lowercased()
            let trackLower = trackName.lowercased()
            
            for track in result.data {
                let deezerArtist = track.artist.name.lowercased()
                let deezerTitle = track.title.lowercased()
                
                // Check if artist matches (contains or is contained)
                let artistMatch = deezerArtist.contains(artistLower) || artistLower.contains(deezerArtist)
                
                // Check if title is similar (contains main words)
                let titleWords = trackLower.split(separator: " ").filter { $0.count > 2 }
                let titleMatch = titleWords.allSatisfy { deezerTitle.contains($0) }
                
                if artistMatch && (titleMatch || deezerTitle.contains(trackLower.prefix(10))) {
                    if let preview = track.preview, !preview.isEmpty {
                        return preview
                    }
                }
            }
            
            // Fallback: return first result with preview if exists
            if let firstWithPreview = result.data.first(where: { $0.preview != nil && !($0.preview?.isEmpty ?? true) }) {
                return firstWithPreview.preview
            }
            
            return nil
        } catch {
            return nil
        }
    }
}

// MARK: - Deezer API Models

struct DeezerSearchResponse: Codable {
    let data: [DeezerTrack]
}

struct DeezerTrack: Codable {
    let id: Int
    let title: String
    let preview: String?
    let artist: DeezerArtist
}

struct DeezerArtist: Codable {
    let id: Int
    let name: String
}
