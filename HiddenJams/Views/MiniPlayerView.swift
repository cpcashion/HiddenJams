//
//  MiniPlayerView.swift
//  HiddenJams
//
//  Persistent bottom-shelf player card. Visible across the whole app
//  whenever audio is loaded — tap a saved song on the profile page and
//  this appears with controls, no more mystery audio.
//

import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject var audioManager: AudioPreviewManager
    var onTapTrack: () -> Void = {}

    var body: some View {
        if let track = audioManager.currentTrack {
            HStack(spacing: 12) {
                // Artwork
                AsyncImage(url: track.track.album.images.first?.url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Theme.Colors.spotifyDarkGray)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(Theme.Colors.textSecondary)
                        )
                }
                .frame(width: 48, height: 48)
                .cornerRadius(8)
                .clipped()

                // Track info — tap to open full player
                Button(action: onTapTrack) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.track.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(track.track.artistNames)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                // Playback controls
                Button(action: { audioManager.togglePlayPause() }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.Colors.textPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Button(action: { audioManager.playNext() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.Colors.textSecondary)
                        .frame(width: 36, height: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.Colors.cardGradient)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: -2)
            )
            .padding(.horizontal, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
