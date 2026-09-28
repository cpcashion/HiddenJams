//
//  MusicSourceManager.swift
//  HiddenJams
//
//  Tracks which music sources (Spotify, Apple Music, or both) the user has
//  connected. The app is "unlocked" when at least one source is connected.
//

import Foundation
import Combine

/// Tracks which music sources (Spotify, Apple Music, or both) the user has
/// connected. Plain class (like SpotifyAuthManager); published state is
/// updated on the main thread.
class MusicSourceManager: ObservableObject {
    @Published private(set) var connectedSources: [MusicSource] = []

    private let spotifyAuth: SpotifyAuthManager
    private let appleMusic: AppleMusicService
    private var cancellables = Set<AnyCancellable>()

    init(spotifyAuth: SpotifyAuthManager, appleMusic: AppleMusicService) {
        self.spotifyAuth = spotifyAuth
        self.appleMusic = appleMusic
        refresh()

        // Keep in sync as auth states change
        spotifyAuth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        appleMusic.$authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    var hasConnectedSource: Bool {
        !connectedSources.isEmpty
    }

    var spotifyConnected: Bool {
        spotifyAuth.isAuthenticated
    }

    var appleMusicConnected: Bool {
        appleMusic.isConnected && appleMusic.isAuthorized
    }

    var summaryText: String {
        switch connectedSources.count {
        case 0: return "No music connected"
        case 1: return "Connected: \(connectedSources[0].displayName)"
        default: return "Connected: \(connectedSources.map { $0.displayName }.joined(separator: " + "))"
        }
    }

    func refresh() {
        var sources: [MusicSource] = []
        if spotifyAuth.isAuthenticated { sources.append(.spotify) }
        if appleMusic.isConnected && appleMusic.isAuthorized { sources.append(.appleMusic) }
        if sources != connectedSources {
            connectedSources = sources
        }
    }

    func disconnect(_ source: MusicSource) {
        switch source {
        case .spotify:
            spotifyAuth.logout()
        case .appleMusic:
            appleMusic.disconnect()
        }
        refresh()
    }
}
