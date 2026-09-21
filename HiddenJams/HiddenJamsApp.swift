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
    @StateObject private var profileAnalyzer = AIProfileAnalyzer()
    @StateObject private var factsService = MusicFactsService()
    @StateObject private var audioManager = AudioPreviewManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(apiService)
                .environmentObject(profileAnalyzer)
                .environmentObject(factsService)
                .environmentObject(audioManager)
                .preferredColorScheme(.dark)
                .task {
                    // Fetch fresh music facts on app launch
                    await factsService.fetchMusicFacts()
                }
        }
    }
}
