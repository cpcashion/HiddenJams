//
//  DashboardView.swift
//  SpotifyHiddenGems
//
//  Clean home page focused on genre selection and discovery
//

import SwiftUI

struct DashboardView: View {
    @ObservedObject var discoveryEngine: EnhancedHiddenGemsDiscovery
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var apiService: SpotifyAPIService
    @EnvironmentObject var audioManager: AudioPreviewManager
    @EnvironmentObject var appleMusicService: AppleMusicService
    
    @State private var showGenreSelection = false
    @State private var showDiscoveryError = false
    @AppStorage("selectedGenres") private var selectedGenresData: Data = Data()
    
    // Popularity slider state
    @StateObject private var popularitySettings = PopularitySliderSettings()
    
    var onShowPlayer: () -> Void = {}
    var onShowProfile: () -> Void = {}
    /// Build 78: a stat pill was tapped — open Profile at that stat.
    var onShowStat: (ProfileStatFocus) -> Void = { _ in }
    
    private var selectedGenres: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: selectedGenresData)) ?? []
    }
    
    init(discoveryEngine: EnhancedHiddenGemsDiscovery,
         onShowPlayer: @escaping () -> Void = {},
         onShowProfile: @escaping () -> Void = {},
         onShowStat: @escaping (ProfileStatFocus) -> Void = { _ in }) {
        self.discoveryEngine = discoveryEngine
        self.onShowPlayer = onShowPlayer
        self.onShowProfile = onShowProfile
        self.onShowStat = onShowStat
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Near-black + plum canvas with pink/purple ambient glow
                Theme.Colors.backgroundGradient.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                        
                        // Analysis needed prompt — also shown when Apple Music
                        // was connected after the last analysis (e.g. a stale
                        // Spotify profile exists but no Apple tracks were read).
                        if (profileAnalyzer.profile.totalTracksAnalyzed == 0 || needsAppleMusicAnalysis) && !profileAnalyzer.isAnalyzing {
                            analyzePromptCard
                        }
                        
                        // Analysis in progress
                        if profileAnalyzer.isAnalyzing {
                            analysisProgressCard
                        }
                        
                        // Main content - only show after analysis
                        if profileAnalyzer.profile.totalTracksAnalyzed > 0 && !profileAnalyzer.isAnalyzing {
                            // Genre Selection
                            genreSelectionSection
                            
                            // Popularity Slider
                            PopularitySliderView(
                                popularityLevel: $popularitySettings.popularityLevel,
                                settings: popularitySettings
                            )
                            
                            // Discover Button
                            discoverButton
                            
                            // Stats summary
                            quickStatsRow
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                
                // Full-screen discovery loading overlay
                if discoveryEngine.isDiscovering {
                    DiscoveryLoadingView(progressMessage: discoveryEngine.discoveryProgress)
                        .transition(.opacity)
                }
            }
            // Concert crowd as BACKGROUND - removes from layout flow
            .background(
                ConcertCrowdView(popularityLevel: $popularitySettings.popularityLevel)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            )
            .navigationBarHidden(true)
            .task {
                if authManager.user == nil, let token = authManager.accessToken {
                    if let user = try? await apiService.getCurrentUser(token: token) {
                        await MainActor.run {
                            authManager.user = user
                            UserDataManager.shared.saveUserProfile(user)
                        }
                    }
                }
                
                if profileAnalyzer.profile.totalTracksAnalyzed == 0 {
                    profileAnalyzer.loadProfile()
                }
                // Keep the taste profile fresh: re-analyze in the background
                // when it's older than a week (taste evolves).
                Task {
                    await profileAnalyzer.refreshIfStale(spotifyToken: authManager.accessToken)
                }
            }
            .sheet(isPresented: $showGenreSelection) {
                GenreSelectionView(topGenres: Array(profileAnalyzer.profile.genreWeights.keys))
            }
            // Surface discovery failures — they used to fail silently, which
            // looked like the app "glitched" back to the dashboard.
            .onChange(of: discoveryEngine.errorMessage) { newValue in
                showDiscoveryError = newValue != nil
            }
            .alert("Couldn't Find New Music", isPresented: $showDiscoveryError) {
                Button("OK") {
                    discoveryEngine.clearError()
                }
            } message: {
                Text(discoveryEngine.errorMessage ?? "Something went wrong. Please try again.")
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeBasedGreeting)
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(Theme.Colors.textPrimary.opacity(0.85))
                
                if let name = userFirstName {
                    Text(name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                }
            }
            
            Spacer()
            
            // Profile button - switches to Profile tab
            Button(action: onShowProfile) {
                if let imageUrl = authManager.user?.images?.first?.url {
                    AsyncImage(url: imageUrl) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else if appleMusicService.isConnected {
                    // Apple Music provides no profile photo: show the user's monster.
                    Image(MonsterAvatar.assignedName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private var timeBasedGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        
        if hour < 12 {
            return "Good morning,"
        } else if hour < 17 {
            return "Good afternoon,"
        } else {
            return "Good evening,"
        }
    }
    
    private var userFirstName: String? {
        authManager.user?.displayName?.components(separatedBy: " ").first
    }
    
    /// True when Apple Music is connected but no Apple Music tracks have been
    /// analyzed yet (e.g. connected after the last analysis, or on a fresh
    /// install with a stale cached profile). Without this the dashboard hides
    /// the analysis prompt and discovery has no seeds.
    private var needsAppleMusicAnalysis: Bool {
        appleMusicService.isConnected
            && !profileAnalyzer.libraryTracks.contains(where: { $0.source == .appleMusic })
    }
    
    // MARK: - Analyze Prompt
    
    private var analyzePromptCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(Theme.Colors.plumButton)
            
            Text("Analyze Your Library")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.Colors.textOnPastel)
            
            Text("We'll analyze your music to find tracks that match your taste")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textOnPastelSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    // Analyzes Spotify, Apple Music, or both — whichever is connected
                    await profileAnalyzer.analyzeAllConnectedSources(spotifyToken: authManager.accessToken)
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("Start Analysis")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .brandGlass(Theme.Colors.plumButton, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .pastelCard(Theme.Colors.lavender, padding: 24)
    }
    
    // MARK: - Analysis Progress
    
    private var analysisProgressCard: some View {
        VStack(spacing: 16) {
            Text("Analyzing Your Music")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text(profileAnalyzer.currentStep)
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            ProgressView(value: profileAnalyzer.analysisProgress)
                .tint(Theme.Colors.lime)
                .scaleEffect(x: 1, y: 1.5)
            
            Text("\(Int(profileAnalyzer.analysisProgress * 100))%")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            RotatingFactsView()
                .padding(.top, 8)
        }
        .padding(24)
        .surfaceCard(radius: Theme.CornerRadius.card)
    }
    
    // MARK: - Genre Selection
    
    private var genreSelectionSection: some View {
        Button(action: { showGenreSelection = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discovering")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    if selectedGenres.isEmpty {
                        Text("All Genres")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                    } else if selectedGenres.count > 3 {
                        // Show count for many genres
                        Text("\(selectedGenres.count) Genres")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                    } else {
                        // Show genre names for 1-3 genres
                        Text(Array(selectedGenres).sorted().joined(separator: ", "))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Genre preview chips (show only 1 to prevent layout issues)
                if let firstGenre = selectedGenres.sorted().first {
                    // Chip wears the genre's own neon color (same mapping as
                    // the genre picker, so colors stay consistent).
                    let chipColor = Theme.Colors.genreColors(for: Array(selectedGenres))[firstGenre.lowercased()]
                        ?? Theme.Colors.gemGold
                    HStack(spacing: 6) {
                Text(firstGenre)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.Colors.textOnGenreColor(chipColor))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(chipColor))
                        
                        if selectedGenres.count > 1 {
                            Text("+\(selectedGenres.count - 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.Colors.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Theme.Colors.chipFill))
                        }
                    }
                }
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.Colors.textOnPastel)
                    .frame(width: 32, height: 32)
                    // Glass on the control affordance only — the card stays
                    // a plain surface (non-interactive: the whole card is the button).
                    .brandGlass(Theme.Colors.lime, in: Circle(), interactive: false)
            }
            .padding(16)
            .surfaceCard(radius: Theme.CornerRadius.card)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Discover Button
    
    private var discoverButton: some View {
        Button(action: {
            Task {
                let token = authManager.accessToken
                // Apple Music-only users seed discovery from their library tracks
                var appleSeeds = token == nil ? profileAnalyzer.libraryTracks : []

                // Self-heal: Apple Music connected but no Apple tracks analyzed
                // yet (e.g. connected after the last analysis). Analyze first
                // so one tap goes from connect → hidden jams, even with a
                // tiny library. The overlay narrates it — the user always
                // sees the app working on their tunes.
                if token == nil && appleSeeds.isEmpty && appleMusicService.isConnected {
                    await MainActor.run { discoveryEngine.isDiscovering = true }
                    await discoveryEngine.updateProgress("Analyzing your Apple Music library...")
                    await profileAnalyzer.analyzeAllConnectedSources(spotifyToken: nil)
                    appleSeeds = profileAnalyzer.libraryTracks
                }

                await discoveryEngine.discoverHiddenGems(
                    profile: profileAnalyzer.profile,
                    userTracks: profileAnalyzer.userLibraryTracks.map { $0.id },
                    userLibrary: profileAnalyzer.userLibraryTracks,
                    selectedGenres: selectedGenres.isEmpty ? nil : selectedGenres,
                    token: token,
                    appleMusicSeeds: appleSeeds,
                    count: 50,
                    popularityOverride: popularitySettings.popularityThreshold,
                    followerOverride: popularitySettings.followerThreshold
                )
                
                if !discoveryEngine.discoveredGems.isEmpty {
                    await MainActor.run {
                        onShowPlayer()
                    }
                }
            }
        }) {
            HStack {
                if discoveryEngine.isDiscovering {
                    ProgressView()
                        .tint(Theme.Colors.textOnPastel)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                }
                
                Text(discoveryEngine.isDiscovering ? "Discovering..." : "Discover")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(Theme.Colors.textOnPastel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .brandGlass(Theme.Colors.lime, in: Capsule())
            .shadow(color: Theme.Colors.lime.opacity(0.25), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(discoveryEngine.isDiscovering)
        .opacity(discoveryEngine.isDiscovering ? 0.7 : 1.0)
    }
    
    // MARK: - Quick Stats
    
    private var quickStatsRow: some View {
        HStack(spacing: 10) {
            // Build 78: each pill opens its stats section in Profile.
            QuickStat(value: "\(profileAnalyzer.profile.totalTracksAnalyzed)", label: "Tracks", tile: Theme.Colors.pink) {
                onShowStat(.tracks)
            }
            QuickStat(value: "\(discoveryEngine.discoveredGems.count)", label: "Gems Found", tile: Theme.Colors.mint) {
                onShowStat(.gems)
            }
            QuickStat(value: "\(profileAnalyzer.profile.genreWeights.count)", label: "Genres", tile: Theme.Colors.butter) {
                onShowStat(.genres)
            }
        }
    }
    
    // MARK: - Recently Discovered
    
    private var recentlyDiscoveredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Discovered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(discoveryEngine.discoveredGems.prefix(6)) { gem in
                        CompactGemCard(gem: gem)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct QuickStat: View {
    let value: String
    let label: String
    /// Pastel tile color (build 76). nil = plain, on the canvas.
    var tile: Color? = nil
    /// Build 78: when set, the tile is a button (with subtle Liquid Glass).
    var action: (() -> Void)? = nil
    
    var body: some View {
        if let tile, let action {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                tileContent(showsChevron: true)
                    .brandGlass(tile, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(value) \(label)")
            .accessibilityHint("Shows your \(label.lowercased()) stats in Profile")
        } else if let tile {
            tileContent(showsChevron: false)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                        .fill(tile)
                )
        } else {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func tileContent(showsChevron: Bool) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundColor(Theme.Colors.textOnPastel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.Colors.textOnPastelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(alignment: .topTrailing) {
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.Colors.textOnPastelSecondary)
                        .padding(10)
                }
            }
    }
}

struct CompactGemCard: View {
    let gem: RecommendedTrack
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: gem.track.album.albumArtURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.2))
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(gem.track.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(gem.track.artistNames)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(width: 100)
        }
    }
}

// Keep existing supporting views
struct StatItem: View {
    let value: String
    let label: String
    let icon: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Theme.Colors.textSecondary)
            
            Text(value)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.textPrimary)
                .fontWeight(.bold)
            
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CompactTrackCard: View {
    let gem: HiddenGem
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            AsyncImage(url: gem.track.album.albumArtURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(Theme.Colors.spotifyDarkGray)
            }
            .frame(width: 120, height: 120)
            .cornerRadius(Theme.CornerRadius.md)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(gem.track.name)
                    .font(Theme.Typography.body2)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(gem.track.artistNames)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 120)
        }
    }
}
