//
//  ExpandedPlayerView.swift
//  HiddenJams
//
//  Full-screen Now Playing sheet. Presented by tapping the mini-player
//  shelf — Spotify-style expand-up with big artwork, scrubber, and
//  transport controls. Drag down or tap the chevron to collapse.
//

import SwiftUI

struct ExpandedPlayerView: View {
    @EnvironmentObject var audioManager: AudioPreviewManager
    @EnvironmentObject var authManager: SpotifyAuthManager
    @Environment(\.dismiss) private var dismiss

    // Scrubbing state: while the user drags, hold the thumb locally so the
    // 0.1s time observer doesn't fight the drag; seek once on release.
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    // Rarity reveal state
    @State private var artistRarity: ArtistRarity?
    @State private var showRaritySheet = false

    var body: some View {
        if let track = audioManager.currentTrack {
            VStack(spacing: 0) {
                // Grabber + collapse
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("Now Playing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)

                Spacer(minLength: 12)

                // Big artwork
                AsyncImage(url: track.track.album.images.first?.url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous)
                        .fill(Theme.Colors.goldGradient)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundColor(Theme.Colors.textSecondary)
                        )
                }
                .frame(maxWidth: 340, maxHeight: 340)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(color: Theme.Colors.magentaGlow.opacity(0.35), radius: 32, y: 10)
                .padding(.horizontal, 32)

                Spacer(minLength: 20)

                // Title + artist — tapping opens the music source.
                VStack(spacing: 6) {
                    Text(track.track.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 32)
                        .onTapGesture { _ = FullSongOpener.openFullSong(for: track) }
                    Text(track.track.artistNames)
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 32)
                        .onTapGesture { _ = FullSongOpener.openFullSong(for: track) }

                    // Rarity pill — tap for the full rarity sheet
                    RarityPill(rarity: artistRarity)
                        .onTapGesture { showRaritySheet = true }
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                .onAppear { loadRarity(for: track) }
                .onChange(of: track.id) { _ in loadRarity(for: track) }

                Spacer(minLength: 16)

                // Scrubber
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { isScrubbing ? scrubValue : audioManager.currentTime },
                            set: { scrubValue = $0 }
                        ),
                        in: 0...max(audioManager.duration, 0.1),
                        onEditingChanged: { editing in
                            if editing {
                                isScrubbing = true
                                scrubValue = audioManager.currentTime
                            } else {
                                isScrubbing = false
                                audioManager.seek(to: scrubValue)
                            }
                        }
                    )
                    .tint(Theme.Colors.lime)
                    .padding(.horizontal, 32)
                    HStack {
                        Text(formatTime(isScrubbing ? scrubValue : audioManager.currentTime))
                        Spacer()
                        Text(formatTime(audioManager.duration))
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.horizontal, 32)
                }

                Spacer(minLength: 12)

                // Transport controls
                // Liquid-glass transport capsule with a lime play disc.
                GlassEffectContainer {
                HStack(spacing: 28) {
                    Button(action: { audioManager.playPrevious() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(width: 52, height: 52)
                            .subtleGlass(in: Circle())
                    }
                    Button(action: { audioManager.togglePlayPause() }) {
                        Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.Colors.textOnPastel)
                            .frame(width: 76, height: 76)
                            .brandGlass(Theme.Colors.lime, in: Circle())
                            .shadow(color: Theme.Colors.lime.opacity(0.35), radius: 18, y: 6)
                    }
                    Button(action: { audioManager.playNext() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .frame(width: 52, height: 52)
                            .subtleGlass(in: Circle())
                    }
                }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.backgroundGradient.ignoresSafeArea())
            .sheet(isPresented: $showRaritySheet) {
                if let rarity = artistRarity, let track = audioManager.currentTrack {
                    RaritySheet(rarity: rarity, trackName: track.track.name)
                }
            }
        }
    }

    private func loadRarity(for track: RecommendedTrack) {
        guard let artist = track.track.artists.first else {
            artistRarity = nil
            return
        }
        if artistRarity?.artistName == artist.name { return }
        artistRarity = nil
        Task {
            let rarity = await RarityService.shared.rarity(
                for: artist,
                spotifyToken: authManager.accessToken
            )
            await MainActor.run {
                if audioManager.currentTrack?.track.artists.first?.name == artist.name {
                    artistRarity = rarity
                }
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
