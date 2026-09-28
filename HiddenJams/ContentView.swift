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
