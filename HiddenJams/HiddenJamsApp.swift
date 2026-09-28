//
//  HiddenJamsApp.swift
//  HiddenJams
//
//  Created by Christopher Cashion on 11/25/25.
//

import SwiftUI

@main
struct HiddenJamsApp: App {
    @StateObject private var authManager = SpotifyAuthManager()
    @StateObject private var apiService = SpotifyAPIService()
    @StateObject private var profileAnalyzer: AIProfileAnalyzer
    @StateObject private var factsService = MusicFactsService()
    @StateObject private var audioManager = AudioPreviewManager()
    @StateObject private var appleMusicService = AppleMusicService()
    @StateObject private var sourceManager: MusicSourceManager

    init() {
        let auth = SpotifyAuthManager()
        let apple = AppleMusicService()
        _authManager = StateObject(wrappedValue: auth)
        _appleMusicService = StateObject(wrappedValue: apple)
        _sourceManager = StateObject(wrappedValue: MusicSourceManager(spotifyAuth: auth, appleMusic: apple))
        _apiService = StateObject(wrappedValue: SpotifyAPIService())
        _profileAnalyzer = StateObject(wrappedValue: AIProfileAnalyzer(appleMusicService: apple))
        _factsService = StateObject(wrappedValue: MusicFactsService())
        _audioManager = StateObject(wrappedValue: AudioPreviewManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(apiService)
                .environmentObject(profileAnalyzer)
                .environmentObject(factsService)
                .environmentObject(audioManager)
                .environmentObject(appleMusicService)
                .environmentObject(sourceManager)
                .preferredColorScheme(.dark)
                .task {
                    // Fetch fresh music facts on app launch
                    await factsService.fetchMusicFacts()
                }
        }
    }
}
