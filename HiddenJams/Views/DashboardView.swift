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
    
    @State private var showGenreSelection = false
    @AppStorage("selectedGenres") private var selectedGenresData: Data = Data()
    
    // Popularity slider state
    @StateObject private var popularitySettings = PopularitySliderSettings()
    
    var onShowPlayer: () -> Void = {}
    var onShowProfile: () -> Void = {}
    
    private var selectedGenres: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: selectedGenresData)) ?? []
    }
    
    init(discoveryEngine: EnhancedHiddenGemsDiscovery, onShowPlayer: @escaping () -> Void = {}, onShowProfile: @escaping () -> Void = {}) {
        self.discoveryEngine = discoveryEngine
        self.onShowPlayer = onShowPlayer
        self.onShowProfile = onShowProfile
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Solid black background
                Color.black.ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        headerView
                        
                        // Analysis needed prompt
                        if profileAnalyzer.profile.totalTracksAnalyzed == 0 && !profileAnalyzer.isAnalyzing {
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
            }
            .sheet(isPresented: $showGenreSelection) {
                GenreSelectionView(topGenres: Array(profileAnalyzer.profile.genreWeights.keys))
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeBasedGreeting)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                if let name = userFirstName {
                    Text(name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
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
    
    // MARK: - Analyze Prompt
    
    private var analyzePromptCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.gemGold)
            
            Text("Analyze Your Library")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text("We'll analyze your music to find tracks that match your taste")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button(action: {
                Task {
                    guard let token = authManager.accessToken else { return }
                    await profileAnalyzer.analyzeCompleteLibrary(token: token)
                }
            }) {
                Text("Start Analysis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.Colors.gemGold)
                    .cornerRadius(12)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Analysis Progress
    
    private var analysisProgressCard: some View {
        VStack(spacing: 16) {
            Text("Analyzing Your Music")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text(profileAnalyzer.currentStep)
                .font(.system(size: 14))
                .foregroundColor(.gray)
            
            ProgressView(value: profileAnalyzer.analysisProgress)
                .tint(.green)
                .scaleEffect(x: 1, y: 1.5)
            
            Text("\(Int(profileAnalyzer.analysisProgress * 100))%")
                .font(.system(size: 12))
                .foregroundColor(.gray)
            
            RotatingFactsView()
                .padding(.top, 8)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
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
                            .foregroundColor(.white)
                    } else if selectedGenres.count > 3 {
                        // Show count for many genres
                        Text("\(selectedGenres.count) Genres")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        // Show genre names for 1-3 genres
                        Text(Array(selectedGenres).sorted().joined(separator: ", "))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Genre preview chips (show only 1 to prevent layout issues)
                if let firstGenre = selectedGenres.sorted().first {
                    HStack(spacing: 6) {
                        Text(firstGenre)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Theme.Colors.gemGold.opacity(0.25)))
                        
                        if selectedGenres.count > 1 {
                            Text("+\(selectedGenres.count - 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.Colors.gemGold)
                        }
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Discover Button
    
    private var discoverButton: some View {
        Button(action: {
            Task {
                guard let token = authManager.accessToken else { return }
                
                await discoveryEngine.discoverHiddenGems(
                    profile: profileAnalyzer.profile,
                    userTracks: profileAnalyzer.userLibraryTracks.map { $0.id },
                    userLibrary: profileAnalyzer.userLibraryTracks,
                    selectedGenres: selectedGenres.isEmpty ? nil : selectedGenres,
                    token: token,
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
                        .tint(.black)
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18))
                }
                
                Text(discoveryEngine.isDiscovering ? "Discovering..." : "Discover")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.gemGold, Theme.Colors.gemGold.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
        }
        .disabled(discoveryEngine.isDiscovering)
        .opacity(discoveryEngine.isDiscovering ? 0.7 : 1.0)
    }
    
    // MARK: - Quick Stats
    
    private var quickStatsRow: some View {
        HStack(spacing: 0) {
            QuickStat(value: "\(profileAnalyzer.profile.totalTracksAnalyzed)", label: "Tracks")
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 40)
            
            QuickStat(value: "\(discoveryEngine.discoveredGems.count)", label: "Gems Found")
            
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1, height: 40)
            
            QuickStat(value: "\(profileAnalyzer.profile.genreWeights.count)", label: "Genres")
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Recently Discovered
    
    private var recentlyDiscoveredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recently Discovered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
            
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
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
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
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(gem.track.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
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
