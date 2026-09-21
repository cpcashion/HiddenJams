import SwiftUI

struct MainTabView: View {
    @StateObject private var discoveryEngine = EnhancedHiddenGemsDiscovery()
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    
    // Auth is likely environment
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var apiService: SpotifyAPIService
    
    @Binding var selectedTab: Tab
    
    // Cache the Hidden Jams playlist ID
    @State private var hiddenJamsPlaylistId: String?
    
    enum Tab {
        case home, player, profile
    }
    
    init(selectedTab: Binding<Tab>) {
        self._selectedTab = selectedTab
        // Hide default tab bar
        UITabBar.appearance().isHidden = true
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main Content - Use ZStack with opacity to KEEP views alive
            // This prevents layout recalculation when switching tabs
            ZStack {
                // Home tab - always exists, visibility controlled by opacity
                DashboardView(
                    discoveryEngine: discoveryEngine,
                    onShowPlayer: { selectedTab = .player },
                    onShowProfile: { selectedTab = .profile }
                )
                .opacity(selectedTab == .home ? 1 : 0)
                .zIndex(selectedTab == .home ? 1 : 0)
                
                // Player tab
                Group {
                    if discoveryEngine.isDiscovering {
                        ZStack {
                            Theme.Colors.backgroundGradient.ignoresSafeArea()
                            DiscoveryLoadingView(progressMessage: discoveryEngine.discoveryProgress)
                        }
                    } else if discoveryEngine.discoveredGems.isEmpty {
                        EmptyPlayerStateView { selectedTab = .home }
                    } else {
                        PlaylistPlayerView(
                            recommendations: discoveryEngine.discoveredGems,
                            onSave: { track in
                                Task {
                                    await saveTrackToHiddenJams(track)
                                }
                            },
                            onMinimize: {
                                selectedTab = .home
                            },
                            onDiscoverMore: {
                                Task {
                                    guard let token = authManager.accessToken else { return }
                                    
                                    var selectedGenres: Set<String>? = nil
                                    if let selectedGenresData = UserDefaults.standard.data(forKey: "selectedGenres"),
                                       let decoded = try? JSONDecoder().decode(Set<String>.self, from: selectedGenresData) {
                                        selectedGenres = decoded
                                    }
                                    
                                    await discoveryEngine.discoverHiddenGems(
                                        profile: profileAnalyzer.profile,
                                        userTracks: profileAnalyzer.userLibraryTracks.map { $0.id },
                                        userLibrary: profileAnalyzer.userLibraryTracks,
                                        selectedGenres: selectedGenres,
                                        token: token,
                                        count: 30,
                                        appendResults: false
                                    )
                                }
                            },
                            isRefreshing: discoveryEngine.isDiscovering,
                            refreshProgress: discoveryEngine.discoveryProgress
                        )
                    }
                }
                .opacity(selectedTab == .player ? 1 : 0)
                .zIndex(selectedTab == .player ? 1 : 0)
                
                // Profile tab - always exists, visibility controlled by opacity
                ProfileView()
                    .environmentObject(profileAnalyzer)
                    .opacity(selectedTab == .profile ? 1 : 0)
                    .zIndex(selectedTab == .profile ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Custom Liquid Tab Bar
            LiquidTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, 20)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Save to Hidden Jams Playlist
    
    private func saveTrackToHiddenJams(_ track: RecommendedTrack) async {
        // Check for token expiration first
        if authManager.isTokenExpired {
            print("🔄 Token expired, refreshing before saving...")
            let refreshed = await withCheckedContinuation { continuation in
                authManager.refreshAccessToken { success in
                    continuation.resume(returning: success)
                }
            }
            guard refreshed else { return }
        }

        guard let token = authManager.accessToken else {
            print("❌ No access token available")
            return
        }
        
        do {
            // Get or create the Hidden Jams playlist
            let playlistId = try await getOrCreateHiddenJamsPlaylist(token: token)
            
            // Add the track to the playlist
            let trackUri = "spotify:track:\(track.id)"
            try await apiService.addTracksToPlaylist(
                playlistId: playlistId,
                uris: [trackUri],
                token: token
            )
            
            print("✅ Successfully saved '\(track.track.name)' to Hidden Jams playlist")
        } catch APIError.httpError(let statusCode) where statusCode == 401 {
            print("⚠️ 401 Unauthorized, attempting to refresh token and retry...")
            let refreshed = await withCheckedContinuation { continuation in
                authManager.refreshAccessToken { success in
                    continuation.resume(returning: success)
                }
            }
            
            if refreshed, let newToken = authManager.accessToken {
                do {
                    // Retry with new token
                    let playlistId = try await getOrCreateHiddenJamsPlaylist(token: newToken)
                    let trackUri = "spotify:track:\(track.id)"
                    try await apiService.addTracksToPlaylist(
                        playlistId: playlistId,
                        uris: [trackUri],
                        token: newToken
                    )
                    print("✅ Successfully saved '\(track.track.name)' to Hidden Jams playlist (after refresh)")
                } catch {
                    print("❌ Failed to save track after retry: \(error)")
                }
            }
        } catch {
            print("❌ Failed to save track to Hidden Jams: \(error)")
        }
    }
    
    private func getOrCreateHiddenJamsPlaylist(token: String) async throws -> String {
        // Return cached ID if available
        if let cachedId = hiddenJamsPlaylistId {
            return cachedId
        }
        
        // Search for existing Hidden Jams playlist
        let playlists = try await apiService.getUserPlaylists(token: token)
        
        if let existingPlaylist = playlists.first(where: { $0.name == "Hidden Jams" }) {
            await MainActor.run {
                hiddenJamsPlaylistId = existingPlaylist.id
            }
            print("📝 Found existing Hidden Jams playlist: \(existingPlaylist.id)")
            return existingPlaylist.id
        }
        
        // Create new playlist if it doesn't exist
        guard let userId = authManager.user?.id else {
            throw NSError(domain: "MainTabView", code: 1, userInfo: [NSLocalizedDescriptionKey: "User ID not available"])
        }
        
        let newPlaylist = try await apiService.createPlaylist(
            userId: userId,
            name: "Hidden Jams",
            description: "Underground gems discovered by Hidden Jams",
            token: token
        )
        
        await MainActor.run {
            hiddenJamsPlaylistId = newPlaylist.id
        }
        
        print("🎵 Created new Hidden Jams playlist: \(newPlaylist.id)")
        return newPlaylist.id
    }
}

struct LiquidTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    
    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 16) {
                LiquidTabButton(
                    activeIcon: "house.fill",
                    inactiveIcon: "house",
                    isSelected: selectedTab == .home
                ) {
                    selectedTab = .home
                }
                
                LiquidTabButton(
                    activeIcon: "play.circle.fill",
                    inactiveIcon: "play.circle",
                    isSelected: selectedTab == .player
                ) {
                    selectedTab = .player
                }
                
                LiquidTabButton(
                    activeIcon: "person.fill",
                    inactiveIcon: "person",
                    isSelected: selectedTab == .profile
                ) {
                    selectedTab = .profile
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 16)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
}

struct LiquidTabButton: View {
    let activeIcon: String
    let inactiveIcon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            Image(systemName: isSelected ? activeIcon : inactiveIcon)
                .font(.system(size: 26, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 60, height: 44)
                .contentShape(Rectangle())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyPlayerStateView: View {
    let action: () -> Void
    
    var body: some View {
        ZStack {
            Theme.Colors.backgroundGradient.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.Colors.textTertiary)
                
                Text("No music yet")
                    .font(Theme.Typography.title)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("Start a discovery session on Home to fill your player")
                    .font(Theme.Typography.body2)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button(action: action) {
                    Text("Go to Home")
                        .font(Theme.Typography.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Theme.Colors.spotifyGreen)
                        .cornerRadius(30)
                }
            }
        }
    }
}

