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
            VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Artwork
                AsyncImage(url: track.track.album.images.first?.url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.Colors.goldGradient)
                        .overlay(
                            Image(systemName: "music.note")
                                .foregroundColor(Theme.Colors.textSecondary)
                        )
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Track info — tapping anywhere on the mini player expands
                // it (build 50). The expanded player handles tap-to-source.
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

                // Playback controls
                Button(action: { audioManager.togglePlayPause() }) {
                    Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.Colors.textOnPastel)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.Colors.lime))
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

                // Progress timeline — thin line with live progress
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.Colors.textSecondary.opacity(0.25))
                            .frame(height: 3)
                        Rectangle()
                            .fill(Theme.Colors.lime)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
            }
            // Frosted liquid-glass shelf (build 76).
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTapTrack)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// 0–1 playback progress for the timeline.
    private var progress: Double {
        let duration = audioManager.duration
        guard duration > 0 else { return 0 }
        return min(max(audioManager.currentTime / duration, 0), 1)
    }
}
