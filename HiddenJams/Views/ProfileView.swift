//
//  ProfileView.swift
//  HiddenJams
//
//  Clean, minimalist profile experience with real Spotify data
//

import SwiftUI
import AuthenticationServices

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
    @StateObject private var subscriptions = SubscriptionManager.shared

    @State private var selectedTimeRange: TimeRange = .longTerm
    @State private var hasLoadedData = false
    @State private var isConnectingAppleMusic = false
    @State private var isLinkingAppleID = false
    @State private var appleIDError: String?
    
    var body: some View {
        ZStack {
            Theme.Colors.spotifyBlack.ignoresSafeArea()
            
            if profileDataService.isLoading && !hasLoadedData {
                loadingView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        headerSection
                        musicSourcesSection
                        if !savedGems.savedTracks.isEmpty {
                            savedGemsSection
                        }
                        if authManager.isAuthenticated {
                            statsSection
                            recentlyPlayedSection
                            topTracksSection
                            topArtistsSection
                            if profileDataService.stats.hasRealAudioFeatures {
                                audioProfileSection
                            }
                            genresSection
                        } else if sourceManager.appleMusicConnected {
                            appleMusicSummarySection
                        }
                        appearanceSection
                        logoutSection
                        Spacer(minLength: 100)                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60) // Account for status bar
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom) // Only ignore bottom safe area for tab bar
        .task {
            if !hasLoadedData, let token = authManager.accessToken {
                await profileDataService.fetchAllProfileData(token: token)
                hasLoadedData = true
            }
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.Colors.textPrimary)
            Text(profileDataService.loadingMessage)
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Avatar: Spotify photo, else monster, else initial.
                if let imageUrl = userProfile.profile.avatarURL {
                    AsyncImage(url: imageUrl) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Theme.Colors.textPrimary.opacity(0.1))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                } else if let monster = userProfile.profile.monsterAvatarName {
                    Image(monster)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else if appleMusicService.isConnected {
                    // Apple Music provides no profile photo: show the user's monster.
                    Image(MonsterAvatar.assignedName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Theme.Colors.textPrimary.opacity(0.1))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Text(String(userProfile.profile.effectiveDisplayName.prefix(1)))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Theme.Colors.textPrimary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(userProfile.profile.effectiveDisplayName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                        if userProfile.isPremium {
                            Text("PREMIUM")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.gemGold)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Your listening profile")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textSecondary)
                }
                
                Spacer()
            }

            // Apple Music users have no verified identity — offer Sign in
            // with Apple to complete their profile (needed for Premium).
            // GATED: hidden until the Sign in with Apple capability is
            // enabled on the App ID + provisioning profile (see
            // HiddenJams.entitlements). The service code is ready.
            #if ENABLE_APPLE_SIGN_IN
            if !userProfile.profile.hasVerifiedIdentity {
                appleIDLinkCard
            }
            #endif
        }
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
        .cornerRadius(16)
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
    
    // MARK: - Stats
    
    private var statsSection: some View {
        HStack(spacing: 0) {
            statItem(value: "\(profileDataService.stats.uniqueTracksCount)", label: "Tracks")
            statItem(value: "\(profileDataService.stats.uniqueArtistsCount)", label: "Artists")
            statItem(value: profileDataService.stats.formattedListeningTime, label: "Recent")
        }
        .padding(.vertical, 20)
        .background(Theme.Colors.textPrimary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Recently Played
    
    private var recentlyPlayedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Recently Played")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(profileDataService.stats.recentlyPlayed.prefix(10)) { play in
                        recentTrackCard(play.track, in: profileDataService.stats.recentlyPlayed.map(\.track))
                    }
                }
            }
        }
    }
    
    private func recentTrackCard(_ track: SpotifyTrack, in list: [SpotifyTrack]) -> some View {
        Button(action: { playTrack(track, from: list) }) {
            VStack(alignment: .leading, spacing: 8) {
                if let url = track.album.images.first?.url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Theme.Colors.textPrimary.opacity(0.1))
                    }
                    .frame(width: 100, height: 100)
                    .cornerRadius(6)
                }
                
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
    
    // MARK: - Top Tracks
    
    private var topTracksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                sectionHeader("Top Tracks")
                Spacer()
                timeRangePicker
            }
            
            VStack(spacing: 0) {
                ForEach(Array(tracksForTimeRange.prefix(5).enumerated()), id: \.element.id) { index, track in
                    trackRow(rank: index + 1, track: track, in: Array(tracksForTimeRange.prefix(5)))
                    if index < 4 {
                        Divider().background(Theme.Colors.textPrimary.opacity(0.1))
                    }
                }
            }
            .background(Theme.Colors.textPrimary.opacity(0.03))
            .cornerRadius(12)
        }
    }
    
    private var tracksForTimeRange: [SpotifyTrack] {
        switch selectedTimeRange {
        case .shortTerm: return profileDataService.stats.topTracksThisMonth
        case .mediumTerm: return profileDataService.stats.topTracksSixMonths
        case .longTerm: return profileDataService.stats.topTracksAllTime
        }
    }
    
    private var timeRangePicker: some View {
        HStack(spacing: 4) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: { selectedTimeRange = range }) {
                    Text(shortLabel(for: range))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(selectedTimeRange == range ? Theme.Colors.buttonText : Theme.Colors.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedTimeRange == range ?
                            Capsule().fill(Theme.Colors.gemGold) :
                            Capsule().fill(Color.clear)
                        )
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.Colors.textPrimary.opacity(0.1)))
    }
    
    private func shortLabel(for range: TimeRange) -> String {
        switch range {
        case .shortTerm: return "4 Weeks"
        case .mediumTerm: return "6 Mo"
        case .longTerm: return "All"
        }
    }
    
    private func trackRow(rank: Int, track: SpotifyTrack, in list: [SpotifyTrack]) -> some View {
        Button(action: { playTrack(track, from: list) }) {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .frame(width: 24)
                
                if let url = track.album.images.first?.url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Theme.Colors.textPrimary.opacity(0.1))
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(4)
                }
                
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
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Top Artists
    
    private var topArtistsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Top Artists")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(Array(profileDataService.stats.topArtistsAllTime.prefix(8).enumerated()), id: \.element.id) { index, artist in
                        artistCard(artist, rank: index + 1)
                    }
                }
            }
        }
    }
    
    private func artistCard(_ artist: SpotifyArtist, rank: Int) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                if let url = artist.images?.first?.url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(Theme.Colors.textPrimary.opacity(0.1))
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Theme.Colors.textPrimary.opacity(0.1))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Text(String(artist.name.prefix(1)))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Theme.Colors.textSecondary)
                        )
                }
                
                if rank <= 3 {
                    Text("\(rank)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.Colors.spotifyBlack)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Theme.Colors.textPrimary))
                }
            }
            
            Text(artist.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
    
    // MARK: - Audio Profile
    
    private var audioProfileSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Audio Profile")
            
            if let features = profileDataService.stats.audioFeatures {
                VStack(spacing: 12) {
                    audioBar("Energy", value: features.energy)
                    audioBar("Danceability", value: features.danceability)
                    audioBar("Positivity", value: features.valence)
                    audioBar("Acoustic", value: features.acousticness)
                }
                .padding(16)
                .background(Theme.Colors.textPrimary.opacity(0.03))
                .cornerRadius(12)
                
                HStack(spacing: 12) {
                    infoChip("Tempo", value: "\(Int(features.tempo)) BPM")
                    infoChip("Loudness", value: "\(Int(features.loudness)) dB")
                }
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
                    Rectangle()
                        .fill(Theme.Colors.textPrimary.opacity(0.1))
                        .cornerRadius(2)
                    Rectangle()
                        .fill(Theme.Colors.textPrimary.opacity(0.8))
                        .cornerRadius(2)
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 4)
            
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.Colors.textSecondary)
                .frame(width: 36, alignment: .trailing)
        }
    }
    
    private func infoChip(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.Colors.textSecondary)
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.Colors.textPrimary.opacity(0.03))
        .cornerRadius(8)
    }
    
    // MARK: - Genres
    
    private var genresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Top Genres")
            
            FlowLayout(spacing: 8) {
                ForEach(profileDataService.stats.topGenres.indices, id: \.self) { index in
                    let genre = profileDataService.stats.topGenres[index]
                    genreChip(genre.name.capitalized)
                }
            }
        }
    }
    
    private func genreChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.Colors.textPrimary.opacity(0.08))
            .cornerRadius(16)
    }
    
    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: 0) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            themeManager.mode = theme
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: theme.iconName)
                                .font(.system(size: 14, weight: .medium))
                            Text(theme.displayName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(themeManager.mode == theme
                                         ? Theme.Colors.buttonText
                                         : Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            themeManager.mode == theme
                            ? Theme.Colors.gemGold
                            : Color.clear
                        )
                        .cornerRadius(10)
                    }
                }
            }
            .padding(4)
            .background(Theme.Colors.textPrimary.opacity(0.08))
            .cornerRadius(14)
        }
    }

    // MARK: - Logout
    
    private var logoutSection: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Theme.Colors.textPrimary.opacity(0.1))
                .padding(.vertical, 8)
            
            Button(action: {
                for source in sourceManager.connectedSources {
                    sourceManager.disconnect(source)
                }
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Disconnect All")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.red.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.Colors.textPrimary.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Music Sources

    private var musicSourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Music Sources")

            sourceRow(
                icon: "music.note.list",
                name: "Spotify",
                connected: sourceManager.spotifyConnected,
                connect: { authManager.startAuth() },
                disconnect: { sourceManager.disconnect(.spotify) }
            )

            sourceRow(
                icon: "apple.logo",
                name: "Apple Music",
                connected: sourceManager.appleMusicConnected,
                connect: { connectAppleMusic() },
                disconnect: { sourceManager.disconnect(.appleMusic) }
            )

            if sourceManager.connectedSources.count == 2 {
                Text("Blending both libraries for analysis")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
        }
    }

    private func sourceRow(icon: String, name: String, connected: Bool, connect: @escaping () -> Void, disconnect: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(connected ? .green : Theme.Colors.textTertiary)
                .frame(width: 28)
            Text(name)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.Colors.textPrimary)
            Spacer()
            if connected {
                Text("Connected")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                Button("Disconnect") { disconnect() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red.opacity(0.9))
                    .padding(.leading, 8)
            } else {
                Button("Connect") { connect() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.Colors.buttonText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.Colors.gemGold)
                    .cornerRadius(16)
                    .disabled(isConnectingAppleMusic)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Theme.Colors.textPrimary.opacity(0.05))
        .cornerRadius(12)
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

    // MARK: - Saved Gems (in-app collection)

    private var savedGemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("My Saved Gems")
                Spacer()
                Text("\(savedGems.savedTracks.count)")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            ForEach(savedGems.savedTracks.prefix(10)) { track in
                trackRow(rank: 0, track: track, in: Array(savedGems.savedTracks.prefix(10)))
            }
        }
    }

    // MARK: - Apple Music Summary (from analyzed profile)

    private var appleMusicSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Your Taste")
            if profileAnalyzer.profile.topArtists.isEmpty {
                Text("Analyze your Apple Music library from the Home tab to see your taste profile.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
            } else {
                ForEach(Array(profileAnalyzer.profile.topArtists.prefix(5).enumerated()), id: \.element.id) { index, artist in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 24)
                        Text(artist.name)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text("\(artist.frequency) plays")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }
                if !profileAnalyzer.profile.genreWeights.isEmpty {
                    Text("Top genres: " + profileAnalyzer.profile.genreWeights.sorted { $0.value > $1.value }.prefix(5).map { $0.key }.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Theme.Colors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    private func playTrack(_ track: SpotifyTrack, from list: [SpotifyTrack]) {
        let index = list.firstIndex(where: { $0.id == track.id }) ?? 0
        audioManager.playSpotifyTracks(list, startingAt: index)
    }
}
