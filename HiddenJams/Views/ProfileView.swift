//
//  ProfileView.swift
//  HiddenJams
//
//  Clean, minimalist profile experience with real Spotify data
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @StateObject private var profileDataService = ProfileDataService()
    @EnvironmentObject var audioManager: AudioPreviewManager
    
    @State private var selectedTimeRange: TimeRange = .longTerm
    @State private var hasLoadedData = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if profileDataService.isLoading && !hasLoadedData {
                loadingView
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 32) {
                        headerSection
                        statsSection
                        recentlyPlayedSection
                        topTracksSection
                        topArtistsSection
                        if profileDataService.stats.hasRealAudioFeatures {
                            audioProfileSection
                        }
                        genresSection
                        logoutSection
                        Spacer(minLength: 100)
                    }
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
                .tint(.white)
            Text(profileDataService.loadingMessage)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(spacing: 16) {
            // Avatar
            if let imageUrl = authManager.user?.images?.first?.url {
                AsyncImage(url: imageUrl) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.white.opacity(0.1))
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(String(authManager.user?.displayName?.prefix(1) ?? "?"))
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(authManager.user?.displayName ?? "")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Your listening profile")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
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
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
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
                        recentTrackCard(play.track)
                    }
                }
            }
        }
    }
    
    private func recentTrackCard(_ track: SpotifyTrack) -> some View {
        Button(action: { playTrack(track) }) {
            VStack(alignment: .leading, spacing: 8) {
                if let url = track.album.images.first?.url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 100, height: 100)
                    .cornerRadius(6)
                }
                
                Text(track.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(track.artistNames)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
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
                    trackRow(rank: index + 1, track: track)
                    if index < 4 {
                        Divider().background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(Color.white.opacity(0.03))
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
                        .foregroundColor(selectedTimeRange == range ? .black : .white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedTimeRange == range ?
                            Capsule().fill(Color.white) :
                            Capsule().fill(Color.clear)
                        )
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
    
    private func shortLabel(for range: TimeRange) -> String {
        switch range {
        case .shortTerm: return "4 Weeks"
        case .mediumTerm: return "6 Mo"
        case .longTerm: return "All"
        }
    }
    
    private func trackRow(rank: Int, track: SpotifyTrack) -> some View {
        Button(action: { playTrack(track) }) {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 24)
                
                if let url = track.album.images.first?.url {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 44, height: 44)
                    .cornerRadius(4)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(track.artistNames)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
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
                        Circle().fill(Color.white.opacity(0.1))
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 72, height: 72)
                        .overlay(
                            Text(String(artist.name.prefix(1)))
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        )
                }
                
                if rank <= 3 {
                    Text("\(rank)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white))
                }
            }
            
            Text(artist.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
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
                .background(Color.white.opacity(0.03))
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
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 90, alignment: .leading)
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .cornerRadius(2)
                    Rectangle()
                        .fill(Color.white.opacity(0.8))
                        .cornerRadius(2)
                        .frame(width: geo.size.width * value)
                }
            }
            .frame(height: 4)
            
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 36, alignment: .trailing)
        }
    }
    
    private func infoChip(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.03))
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
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .cornerRadius(16)
    }
    
    // MARK: - Logout
    
    private var logoutSection: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 8)
            
            Button(action: {
                authManager.logout()
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Log Out")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.red.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }
        }
        .padding(.top, 16)
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.4))
            .textCase(.uppercase)
            .tracking(0.5)
    }
    
    private func playTrack(_ track: SpotifyTrack) {
        if let previewUrl = track.previewUrl {
            audioManager.playPreview(url: previewUrl, trackId: track.id)
        }
    }
}
