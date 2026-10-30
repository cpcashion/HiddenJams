//
//  ProfileView.swift
//  HiddenJams
//
//  Build 79: Profile simplified into an iOS-style grouped screen.
//    • compact header (avatar, name, connected services)
//    • "Your stats": three summary rows that push detail screens
//      (Home's stat pills deep-link straight to the matching one)
//    • "Your music": saved gems + listening detail behind a tap
//    • Playlists / Music services / Appearance / Disconnect settings
//  The old duplicate blocks (Spotify stat tiles, Top Genres chips, inline
//  saved-gems list) were folded into the stat detail screens.
//

import SwiftUI
import AuthenticationServices

/// Screens pushed from Profile.
enum ProfileRoute: Hashable {
    case stat(ProfileStatFocus)
    case listening
    case savedGems
}

struct ProfileView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var appleMusicService: AppleMusicService
    @EnvironmentObject var sourceManager: MusicSourceManager
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @StateObject private var profileDataService = ProfileDataService()
    @StateObject private var savedGems = SavedGemsStore.shared
    @EnvironmentObject var audioManager: AudioPreviewManager
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var userProfile = UserProfileManager.shared

    /// Build 79: off = every save goes to one "Hidden Jams" playlist.
    @AppStorage(GenrePlaylistRouter.separateByGenreKey) private var separateByGenre = false

    @State private var path: [ProfileRoute] = []
    @State private var hasLoadedData = false
    @State private var isConnectingAppleMusic = false
    @State private var isLinkingAppleID = false
    @State private var appleIDError: String?
    @State private var confirmDisconnectAll = false

    /// Build 78: set by a Home stat pill. Build 79: Profile pushes that
    /// stat's detail screen, then clears it.
    @Binding var statFocus: ProfileStatFocus?
    /// Gems in the current discovery deck (Home's "Gems Found").
    var deckGemCount: Int = 0

    init(statFocus: Binding<ProfileStatFocus?> = .constant(nil), deckGemCount: Int = 0) {
        self._statFocus = statFocus
        self.deckGemCount = deckGemCount
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.Colors.backgroundGradient.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        headerSection
                        statsGroup
                        musicGroup
                        playlistsGroup
                        servicesGroup
                        appearanceGroup
                        if !sourceManager.connectedSources.isEmpty {
                            disconnectGroup
                        }
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60) // Account for status bar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProfileRoute.self) { route in
                destination(for: route)
            }
        }
        .tint(Theme.Colors.textPrimary)
        .edgesIgnoringSafeArea(.bottom) // Only ignore bottom safe area for tab bar
        .onAppear { applyStatFocus() }
        .onChange(of: statFocus) { _, _ in applyStatFocus() }
        .task {
            if !hasLoadedData, let token = authManager.accessToken {
                await profileDataService.fetchAllProfileData(token: token)
                hasLoadedData = true
            }
        }
        .confirmationDialog("Disconnect all music services?",
                            isPresented: $confirmDisconnectAll,
                            titleVisibility: .visible) {
            Button("Disconnect All", role: .destructive) {
                for source in sourceManager.connectedSources {
                    sourceManager.disconnect(source)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your playlists in Spotify and Apple Music stay as they are.")
        }
    }

    // MARK: - Navigation

    /// Home pill → open that stat's detail screen.
    private func applyStatFocus() {
        guard let focus = statFocus else { return }
        path = [.stat(focus)]
        statFocus = nil
    }

    @ViewBuilder
    private func destination(for route: ProfileRoute) -> some View {
        switch route {
        case .stat(let focus):
            ProfileStatDetailView(focus: focus, deckGemCount: deckGemCount)
        case .listening:
            ProfileListeningView(data: profileDataService)
        case .savedGems:
            SavedGemsListView()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                avatar
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(userProfile.profile.effectiveDisplayName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        if userProfile.isPremium {
                            Text("PREMIUM")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Theme.Colors.buttonText)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.ctaFill)
                                .cornerRadius(4)
                        }
                    }
                    Text(connectedSummary)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            // GATED: hidden until the Sign in with Apple capability is
            // enabled on the App ID + provisioning profile.
            #if ENABLE_APPLE_SIGN_IN
            if !userProfile.profile.hasVerifiedIdentity {
                appleIDLinkCard
            }
            #endif
        }
    }

    @ViewBuilder
    private var avatar: some View {
        // Spotify photo, else monster, else initial.
        if let imageUrl = userProfile.profile.avatarURL {
            AsyncImage(url: imageUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Theme.Colors.textPrimary.opacity(0.1))
            }
        } else if let monster = userProfile.profile.monsterAvatarName {
            Image(monster).resizable().scaledToFill()
        } else if appleMusicService.isConnected {
            // Apple Music provides no profile photo: show the user's monster.
            Image(MonsterAvatar.assignedName).resizable().scaledToFill()
        } else {
            Circle()
                .fill(Theme.Colors.textPrimary.opacity(0.1))
                .overlay(
                    Text(String(userProfile.profile.effectiveDisplayName.prefix(1)))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(Theme.Colors.textPrimary)
                )
        }
    }

    private var connectedSummary: String {
        var names: [String] = []
        if sourceManager.spotifyConnected { names.append("Spotify") }
        if sourceManager.appleMusicConnected { names.append("Apple Music") }
        return names.isEmpty ? "No music service connected" : names.joined(separator: " · ")
    }

    // MARK: - Sign in with Apple

    private var appleIDLinkCard: some View {
        VStack(spacing: 8) {
            if let err = appleIDError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.error)
            }
            Button(action: linkAppleID) {
                HStack {
                    Image(systemName: "apple.logo")
                    Text(isLinkingAppleID ? "Connecting…" : "Complete your profile with Apple ID")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.black)
                .cornerRadius(12)
            }
            .disabled(isLinkingAppleID)
            Text("Unlocks Premium, sync, and support.")
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .padding(12)
        .background(Theme.Colors.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous))
    }

    private func linkAppleID() {
        isLinkingAppleID = true
        appleIDError = nil
        Task {
            do {
                let credential = try await AppleSignInService.shared.signIn()
                UserProfileManager.shared.linkAppleID(
                    userIdentifier: credential.user,
                    fullName: credential.fullName,
                    email: credential.email
                )
            } catch let e as AppleSignInError {
                if case .cancelled = e { /* silent */ }
                else { appleIDError = e.localizedDescription }
            } catch {
                appleIDError = error.localizedDescription
            }
            isLinkingAppleID = false
        }
    }

    // MARK: - Your stats

    private var statsGroup: some View {
        ProfileGroup("Your stats") {
            navRow(.stat(.tracks), focus: .tracks, value: "\(profileAnalyzer.profile.totalTracksAnalyzed)")
            ProfileRowDivider()
            navRow(.stat(.gems), focus: .gems, value: "\(deckGemCount)")
            ProfileRowDivider()
            navRow(.stat(.genres), focus: .genres, value: "\(profileAnalyzer.profile.genreWeights.count)")
        }
    }

    private func navRow(_ route: ProfileRoute, focus: ProfileStatFocus, value: String) -> some View {
        NavigationLink(value: route) {
            ProfileRowLabel(icon: focus.iconName, tint: focus.tint, title: focus.title, value: value, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Your music

    private var musicGroup: some View {
        ProfileGroup("Your music") {
            NavigationLink(value: ProfileRoute.savedGems) {
                ProfileRowLabel(icon: "heart.fill", tint: Theme.Colors.lime, title: "Saved gems",
                                value: "\(savedGems.savedTracks.count)", showsChevron: true)
            }
            .buttonStyle(.plain)
            if authManager.isAuthenticated || sourceManager.appleMusicConnected {
                ProfileRowDivider()
                NavigationLink(value: ProfileRoute.listening) {
                    ProfileRowLabel(icon: "waveform", tint: Theme.Colors.lavender,
                                    title: authManager.isAuthenticated ? "Top tracks & artists" : "Your taste",
                                    value: nil, showsChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Playlists

    private var playlistsGroup: some View {
        ProfileGroup("Playlists", footer: separateByGenre
            ? "Saves go into a playlist per genre, like \"HJ - House\". Existing playlists aren't changed."
            : "Every save goes into one \"\(GenrePlaylistRouter.singlePlaylistName)\" playlist in your music app. Existing playlists aren't changed.") {
            Toggle(isOn: $separateByGenre) {
                ProfileRowLabel(icon: "square.stack.3d.up.fill", tint: Theme.Colors.peach,
                                title: "Separate playlists by genre", value: nil, showsChevron: false)
            }
            .tint(Theme.Colors.ctaFill)
            .padding(.trailing, 16)
        }
    }

    // MARK: - Music services

    private var servicesGroup: some View {
        ProfileGroup("Music services",
                     footer: sourceManager.connectedSources.count == 2 ? "Blending both libraries for your recommendations." : nil) {
            sourceRow(
                icon: "music.note.list",
                name: "Spotify",
                connected: sourceManager.spotifyConnected,
                connect: { authManager.startAuth() },
                disconnect: { sourceManager.disconnect(.spotify) }
            )
            ProfileRowDivider()
            sourceRow(
                icon: "apple.logo",
                name: "Apple Music",
                connected: sourceManager.appleMusicConnected,
                connect: { connectAppleMusic() },
                disconnect: { sourceManager.disconnect(.appleMusic) }
            )
        }
    }

    private func sourceRow(icon: String, name: String, connected: Bool,
                           connect: @escaping () -> Void, disconnect: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ProfileIconBadge(icon: icon, tint: connected ? Theme.Colors.lime : Theme.Colors.chipFill,
                             foreground: connected ? Theme.Colors.textOnPastel : Theme.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.Colors.textPrimary)
                Text(connected ? "Connected" : "Not connected")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            Spacer()
            if connected {
                Menu {
                    Button("Disconnect \(name)", role: .destructive) { disconnect() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .subtleGlass(in: Circle())
                }
                .accessibilityLabel("\(name) options")
            } else {
                Button("Connect") { connect() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.buttonText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .brandGlass(Theme.Colors.ctaFill, in: Capsule())
                    .disabled(isConnectingAppleMusic)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func connectAppleMusic() {
        isConnectingAppleMusic = true
        Task {
            let authorized = await appleMusicService.requestAuthorization()
            await MainActor.run {
                isConnectingAppleMusic = false
                if authorized {
                    sourceManager.refresh()
                }
            }
            if authorized {
                // Analyze the newly connected library
                await profileAnalyzer.analyzeAllConnectedSources(spotifyToken: authManager.accessToken)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceGroup: some View {
        ProfileGroup("Appearance") {
            HStack(spacing: 0) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.mode = theme
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: theme.iconName)
                                .font(.system(size: 13, weight: .medium))
                            Text(theme.displayName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(themeManager.mode == theme
                                         ? Theme.Colors.buttonText
                                         : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(
                            themeManager.mode == theme
                            ? .regular.tint(Theme.Colors.ctaFill.opacity(0.55)).interactive()
                            : .identity,
                            in: Capsule()
                        )
                        .background(
                            themeManager.mode == theme
                            ? Theme.Colors.ctaFill
                            : Color.clear
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Theme.Colors.chipFill))
            .padding(12)
        }
    }

    // MARK: - Disconnect

    private var disconnectGroup: some View {
        ProfileGroup(nil) {
            Button(action: { confirmDisconnectAll = true }) {
                Text("Disconnect All")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.Colors.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Grouped building blocks (inset-grouped look over the ambient background)

struct ProfileGroup<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(_ title: String?, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.leading, 16)
            }
            VStack(spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                        .fill(Theme.Colors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg, style: .continuous)
                        .stroke(Theme.Colors.textPrimary.opacity(0.06), lineWidth: 0.5)
                )
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }
}

struct ProfileRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.textPrimary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 58)
    }
}

struct ProfileIconBadge: View {
    let icon: String
    let tint: Color
    var foreground: Color = Theme.Colors.textOnPastel

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(foreground)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
    }
}

struct ProfileRowLabel: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String?
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProfileIconBadge(icon: icon, tint: tint)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .monospacedDigit()
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, showsChevron ? 16 : 0)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Pushed screens

/// Shared chrome for screens pushed from Profile.
private struct ProfileDetailScreen<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            Theme.Colors.backgroundGradient.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                content
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

/// One stat (Tracks / Gems / Genres) — the Home pills land here.
struct ProfileStatDetailView: View {
    let focus: ProfileStatFocus
    let deckGemCount: Int

    var body: some View {
        ProfileDetailScreen(focus.title) {
            ProfileStatsView(deckGemCount: deckGemCount, highlighted: nil, only: focus)
        }
    }
}

/// Everything saved in-app, newest first; tap to play, long-press to remove.
struct SavedGemsListView: View {
    @ObservedObject private var savedGems = SavedGemsStore.shared
    @EnvironmentObject var audioManager: AudioPreviewManager

    var body: some View {
        ProfileDetailScreen("Saved gems") {
            if savedGems.savedTracks.isEmpty {
                Text("Swipe right on a track in a discovery session to save it here.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProfileGroup(nil) {
                    ForEach(Array(savedGems.savedTracks.enumerated()), id: \.element.id) { index, track in
                        if index > 0 { ProfileRowDivider() }
                        ProfileTrackRow(rank: nil, track: track) {
                            let list = savedGems.savedTracks
                            audioManager.playSpotifyTracks(list, startingAt: index)
                        }
                        .contextMenu {
                            Button("Remove from Saved", systemImage: "trash", role: .destructive) {
                                savedGems.remove(track)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Spotify top tracks / artists / recently played / audio profile, or the
/// Apple Music taste summary — moved off the main Profile page.
struct ProfileListeningView: View {
    @ObservedObject var data: ProfileDataService
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @EnvironmentObject var audioManager: AudioPreviewManager

    @State private var selectedTimeRange: TimeRange = .longTerm

    var body: some View {
        ProfileDetailScreen(authManager.isAuthenticated ? "Listening" : "Your taste") {
            if authManager.isAuthenticated {
                if data.isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(Theme.Colors.textPrimary)
                        Text(data.loadingMessage)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        topTracksSection
                        if !data.stats.topArtistsAllTime.isEmpty { topArtistsSection }
                        if !data.stats.recentlyPlayed.isEmpty { recentlyPlayedSection }
                        if data.stats.hasRealAudioFeatures { audioProfileSection }
                    }
                }
            } else {
                appleMusicSummary
            }
        }
    }

    // MARK: Top tracks

    private var topTracksSection: some View {
        let tracks = Array(tracksForTimeRange.prefix(5))
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Time range", selection: $selectedTimeRange) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    Text(shortLabel(for: range)).tag(range)
                }
            }
            .pickerStyle(.segmented)

            ProfileGroup("Top tracks") {
                if tracks.isEmpty {
                    Text("No top tracks for this period yet.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(16)
                } else {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        if index > 0 { ProfileRowDivider() }
                        ProfileTrackRow(rank: index + 1, track: track) {
                            audioManager.playSpotifyTracks(tracks, startingAt: index)
                        }
                    }
                }
            }
        }
    }

    private func shortLabel(for range: TimeRange) -> String {
        switch range {
        case .shortTerm: return "4 Weeks"
        case .mediumTerm: return "6 Months"
        case .longTerm: return "All Time"
        }
    }

    private var tracksForTimeRange: [SpotifyTrack] {
        switch selectedTimeRange {
        case .shortTerm: return data.stats.topTracksThisMonth
        case .mediumTerm: return data.stats.topTracksSixMonths
        case .longTerm: return data.stats.topTracksAllTime
        }
    }

    // MARK: Top artists

    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Top artists")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(data.stats.topArtistsAllTime.prefix(8).enumerated()), id: \.element.id) { index, artist in
                        artistCard(artist, rank: index + 1)
                    }
                }
            }
        }
    }

    private func artistCard(_ artist: SpotifyArtist, rank: Int) -> some View {
        VStack(spacing: 8) {
            Group {
                if let url = artist.images?.first?.url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Theme.Colors.textPrimary.opacity(0.1))
                    }
                } else {
                    Circle()
                        .fill(Theme.Colors.textPrimary.opacity(0.1))
                        .overlay(
                            Text(String(artist.name.prefix(1)))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Theme.Colors.textSecondary)
                        )
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())

            Text(artist.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 72)
        }
    }

    // MARK: Recently played

    private var recentlyPlayedSection: some View {
        let list = data.stats.recentlyPlayed.map(\.track)
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recently played")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(list.prefix(10).enumerated()), id: \.offset) { index, track in
                        Button(action: { audioManager.playSpotifyTracks(list, startingAt: index) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: track.album.images.first?.url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Rectangle().fill(Theme.Colors.textPrimary.opacity(0.1))
                                }
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(track.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Text(track.artistNames)
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Audio profile

    private var audioProfileSection: some View {
        ProfileGroup("Audio profile") {
            if let features = data.stats.audioFeatures {
                VStack(spacing: 12) {
                    audioBar("Energy", value: features.energy)
                    audioBar("Danceability", value: features.danceability)
                    audioBar("Positivity", value: features.valence)
                    audioBar("Acoustic", value: features.acousticness)
                    HStack {
                        Text("Tempo \(Int(features.tempo)) BPM")
                        Spacer()
                        Text("Loudness \(Int(features.loudness)) dB")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
                }
                .padding(16)
            }
        }
    }

    private func audioBar(_ label: String, value: Double) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.textPrimary.opacity(0.1))
                    Capsule().fill(Theme.Colors.lime)
                        .frame(width: geo.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 4)
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: Apple Music

    @ViewBuilder
    private var appleMusicSummary: some View {
        if profileAnalyzer.profile.topArtists.isEmpty {
            Text("Analyze your Apple Music library from the Home tab to see your taste profile.")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ProfileGroup("Top artists") {
                ForEach(Array(profileAnalyzer.profile.topArtists.prefix(5).enumerated()), id: \.element.id) { index, artist in
                    if index > 0 { ProfileRowDivider() }
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 30)
                        Text(artist.name)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(artist.frequency) plays")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.leading, 16)
    }
}

/// Artwork + title row used in the pushed Profile lists.
struct ProfileTrackRow: View {
    let rank: Int?
    let track: SpotifyTrack
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                if let rank {
                    Text("\(rank)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: 22)
                }
                AsyncImage(url: track.album.images.first?.url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.chipFill)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
