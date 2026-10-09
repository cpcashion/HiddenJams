//
//  FullSongOpener.swift
//  HiddenJams
//
//  "Play the full song" — opens the native Spotify or Apple Music app.
//  The app streams 30-second previews; when a user loves one, this takes
//  them to the full track with one tap. Centralized so the swipe card,
//  expanded player, and anywhere else share the same logic.
//

import UIKit

enum FullSongOpener {
    /// Which service hosts the full track.
    enum Service {
        case spotify(trackId: String)
        case appleMusic(url: URL)

        var displayName: String {
            switch self {
            case .spotify: return "Spotify"
            case .appleMusic: return "Apple Music"
            }
        }
    }

    /// Resolves the full-song destination for a track, or nil if none.
    static func service(for track: RecommendedTrack) -> Service? {
        // Spotify-origin tracks: spotify:track:{id}
        if track.track.isSpotifyOrigin {
            let id = track.track.id
            if !id.isEmpty { return .spotify(trackId: id) }
        }
        // Also handle raw spotify:track: URIs in spotifyURI.
        if track.spotifyURI.hasPrefix("spotify:track:") {
            let id = String(track.spotifyURI.dropFirst("spotify:track:".count))
            if !id.isEmpty { return .spotify(trackId: id) }
        }
        // iTunes / Apple Music tracks carry the store page URL.
        if let url = URL(string: track.track.uri),
           url.scheme?.hasPrefix("http") == true {
            return .appleMusic(url: url)
        }
        return nil
    }

    /// Resolves the full-song destination for a raw SpotifyTrack.
    static func service(for track: SpotifyTrack) -> Service? {
        if track.isSpotifyOrigin {
            let id = track.id
            if !id.isEmpty { return .spotify(trackId: id) }
        }
        if let url = URL(string: track.uri),
           url.scheme?.hasPrefix("http") == true {
            return .appleMusic(url: url)
        }
        return nil
    }

    /// Resolves the full-song destination for a HiddenGem (swipe card).
    static func service(for gem: HiddenGem) -> Service? {
        service(for: gem.track)
    }

    /// Opens the full song. Tries the native app first, falls back to web.
    static func open(_ service: Service) {
        switch service {
        case .spotify(let trackId):
            let appURL = URL(string: "spotify:track:\(trackId)")
            let webURL = URL(string: "https://open.spotify.com/track/\(trackId)")
            if let appURL, UIApplication.shared.canOpenURL(appURL) {
                UIApplication.shared.open(appURL)
            } else if let webURL {
                UIApplication.shared.open(webURL)
            }
        case .appleMusic(let url):
            UIApplication.shared.open(url)
        }
    }

    /// Convenience: resolve + open in one call. Returns false if no
    /// destination exists for the track.
    @discardableResult
    static func openFullSong(for track: RecommendedTrack) -> Bool {
        guard let service = service(for: track) else { return false }
        open(service)
        return true
    }

    /// Convenience overload for raw SpotifyTrack.
    @discardableResult
    static func openFullSong(for track: SpotifyTrack) -> Bool {
        guard let service = service(for: track) else { return false }
        open(service)
        return true
    }

    /// Convenience overload for HiddenGem (swipe card).
    @discardableResult
    static func openFullSong(for gem: HiddenGem) -> Bool {
        guard let service = service(for: gem) else { return false }
        open(service)
        return true
    }
}
