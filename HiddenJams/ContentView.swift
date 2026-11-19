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
    /// Set ONLY by the taste profile's final "Start digging" (onboarding
    /// v5). Existing installs already have it: earlier builds set it on
    /// every launch with a connected source.
    @AppStorage(DiscoveryQuotaManager.onboardingCompletedKey) private var onboardingCompleted = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background gradient
            Theme.Colors.backgroundGradient
                .ignoresSafeArea()

            if sourceManager.hasConnectedSource && onboardingCompleted {
                MainTabView(selectedTab: $selectedTab)
                    .environmentObject(audioManager)
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(1)

                // Persistent mini-player shelf — visible on every tab
                // whenever audio is loaded. Tap to expand into the full
                // Now Playing screen. This is the ONLY playback chrome;
                // the swipe deck is pure discovery.
                MiniPlayerView(onTapTrack: { showExpandedPlayer = true })
                    .environmentObject(audioManager)
                    .zIndex(2)
                    .padding(.bottom, 92)
                    .animation(.easeInOut, value: audioManager.currentTrack?.id)
            } else if sourceManager.hasConnectedSource {
                // Connected, onboarding not finished: analysis + taste
                // profile reveal, then MainTabView.
                TasteProfileFlowView(onFinish: {
                    withAnimation(.easeInOut) { onboardingCompleted = true }
                })
                .transition(.opacity)
                .zIndex(2)
            } else {
                // Show Onboarding (which now includes Login/Connect) whenever no music source is connected
                OnboardingView(isPresented: .constant(true))
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(2)
            }
        }
        .animation(.easeInOut, value: sourceManager.hasConnectedSource)
        .animation(.easeInOut, value: onboardingCompleted)
        .sheet(isPresented: $showExpandedPlayer) {
            ExpandedPlayerView()
                .environmentObject(audioManager)
        }
        .onAppear {
            // The watch's "open in source app" tap reads the live player.
            let manager = audioManager
            SourceAppOpener.shared.currentTrackProvider = { [weak manager] in
                manager?.currentTrack
            }
            // Onboarding completion is no longer implied by a connection:
            // it's set by TasteProfileFlowView's "Start digging".
        }
        .onOpenURL { url in
            // Handle OAuth callback
            authManager.handleCallback(url: url)
        }
    }
}
