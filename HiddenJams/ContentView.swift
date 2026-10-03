//
//  ContentView.swift
//  SpotifyHiddenGems
//
//  Root view coordinator
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var sourceManager: MusicSourceManager

    @StateObject private var audioManager = AudioPreviewManager()
    @State private var selectedTab: MainTabView.Tab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background gradient
            Theme.Colors.backgroundGradient
                .ignoresSafeArea()

            if sourceManager.hasConnectedSource {
                MainTabView(selectedTab: $selectedTab)
                    .environmentObject(audioManager)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)

                // Persistent mini-player shelf — visible on every tab
                // whenever audio is loaded. Tap the track info to jump
                // to the full player tab.
                MiniPlayerView(onTapTrack: { selectedTab = .player })
                    .environmentObject(audioManager)
                    .zIndex(2)
                    .padding(.bottom, 92)
                    .animation(.easeInOut, value: audioManager.currentTrack?.id)
            } else {
                // Show Onboarding (which now includes Login/Connect) whenever no music source is connected
                OnboardingView(isPresented: .constant(true))
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut, value: sourceManager.hasConnectedSource)
        .onOpenURL { url in
            // Handle OAuth callback
            authManager.handleCallback(url: url)
        }
    }
}
