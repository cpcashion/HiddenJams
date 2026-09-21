//
//  DiscoveryView.swift
//  SpotifyHiddenGems
//
//  Premium feed of hidden gems discovered from across Spotify
//

import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @ObservedObject var discoveryEngine: EnhancedHiddenGemsDiscovery
    let userTracks: [String]
    
    // Audio preview manager
    @StateObject private var audioPreview = AudioPreviewManager()
    
    // Convert to HiddenGem for display
    var hiddenGems: [HiddenGem] {
        discoveryEngine.discoveredGems.map { $0.toHiddenGem() }
    }
    
    @Environment(\.dismiss) var dismiss
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.backgroundGradient
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.lg) {
                        if discoveryEngine.isDiscovering {
                            loadingView
                        } else if hiddenGems.isEmpty {
                            emptyStateView
                        } else {
                            gemsGrid
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xxl)
                }
                .refreshable {
                    await refresh()
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            // Animated icon
            ZStack {
                Circle()
                    .stroke(Theme.Colors.spotifyGreen.opacity(0.2), lineWidth: 3)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Theme.Colors.spotifyGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(discoveryRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            discoveryRotation = 360
                        }
                    }
                
                Image(systemName: "waveform")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.Colors.spotifyGreen)
            }
            
            VStack(spacing: Theme.Spacing.sm) {
                Text("Finding music just for you...")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text(discoveryEngine.discoveryProgress)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Music Facts Section
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("DID YOU KNOW?")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary.opacity(0.6))
                    .tracking(1)
                
                RotatingFactsView()
            }
            .padding(.top, Theme.Spacing.xl)
            
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
    
    @State private var discoveryRotation: Double = 0
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 60))
                .foregroundColor(Theme.Colors.spotifyGreen)
            
            Text("No Gems Found")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text("Pull to refresh and discover new music")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    // MARK: - Gems Grid
    
    private var gemsGrid: some View {
        LazyVStack(spacing: Theme.Spacing.md) {
            ForEach(hiddenGems) { gem in
                TrackCard(gem: gem, audioPreview: audioPreview)
            }
        }
    }
    
    // MARK: - Refresh
    
    private func refresh() async {
        // Implement refresh logic
    }
}

// MARK: - Track Card

struct TrackCard: View {
    let gem: HiddenGem
    @ObservedObject var audioPreview: AudioPreviewManager
    
    private var isPlaying: Bool {
        audioPreview.isPlaying && audioPreview.currentTrackId == gem.id
    }
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Album Art
            AsyncImage(url: gem.track.album.albumArtURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Theme.Colors.spotifyDarkGray)
            }
            .frame(width: 70, height: 70)
            .cornerRadius(Theme.CornerRadius.md)
            
            // Track Info
            VStack(alignment: .leading, spacing: 4) {
                Text(gem.track.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(gem.track.artistNames)
                    .font(Theme.Typography.body2)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
                
                // Match Score
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                    Text("\(Int(gem.matchScore))% match")
                        .font(Theme.Typography.caption)
                }
                .foregroundColor(Theme.Colors.spotifyGreen)
            }
            
            Spacer()
            
            // PROMINENT PLAY BUTTON
            Button(action: {
                handlePlayTap()
            }) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.spotifyGreen)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .fill(Theme.Colors.cardGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                .stroke(isPlaying ? Theme.Colors.spotifyGreen : Color.white.opacity(0.08), lineWidth: isPlaying ? 2 : 1)
        )
        .applyShadow(Theme.Shadows.medium)
    }
    
    private func handlePlayTap() {
        if isPlaying {
            audioPreview.pause()
        } else {
            // Try preview first
            if let previewURL = gem.track.previewUrl {
                audioPreview.playPreview(url: previewURL, trackId: gem.id)
            } else {
                // No preview - open in Spotify app
                openInSpotify()
            }
        }
    }
    
    private func openInSpotify() {
        // Spotify URI format: spotify:track:TRACK_ID
        let spotifyURI = gem.track.uri
        
        // Try to open in Spotify app
        if let url = URL(string: spotifyURI) {
            UIApplication.shared.open(url) { success in
                if !success {
                    print("❌ Could not open Spotify - app not installed?")
                }
            }
        }
    }
}
