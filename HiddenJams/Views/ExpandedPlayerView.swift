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
    @Environment(\.dismiss) private var dismiss

    // Scrubbing state: while the user drags, hold the thumb locally so the
    // 0.1s time observer doesn't fight the drag; seek once on release.
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.Colors.spotifyDarkGray)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 64))
                                .foregroundColor(Theme.Colors.textSecondary)
                        )
                }
                .frame(maxWidth: 340, maxHeight: 340)
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(16)
                .clipped()
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
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
                }

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
                    .tint(Theme.Colors.gemGold)
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
                HStack(spacing: 40) {
                    Button(action: { audioManager.playPrevious() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    Button(action: { audioManager.togglePlayPause() }) {
                        Image(systemName: audioManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                    Button(action: { audioManager.playNext() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }
                }
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.backgroundGradient.ignoresSafeArea())
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}
