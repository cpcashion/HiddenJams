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
    @State private var showExpandedPlayer = false

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
                // EXCEPT the player tab (which has its own full controls).
                // Tap to expand into the full Now Playing screen.
                if selectedTab != .player {
                    MiniPlayerView(onTapTrack: { showExpandedPlayer = true })
                        .environmentObject(audioManager)
                        .zIndex(2)
                        .padding(.bottom, 92)
                        .animation(.easeInOut, value: audioManager.currentTrack?.id)
                }
            } else {
                // Show Onboarding (which now includes Login/Connect) whenever no music source is connected
                OnboardingView(isPresented: .constant(true))
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut, value: sourceManager.hasConnectedSource)
        .sheet(isPresented: $showExpandedPlayer) {
            ExpandedPlayerView()
                .environmentObject(audioManager)
        }
        .onOpenURL { url in
            // Handle OAuth callback
            authManager.handleCallback(url: url)
        }
    }
}
