//
//  ContentView.swift
//  HiddenJamsWatch
//
//  Now-playing mini player on top (track + artist + play/pause), emoji
//  thumbs down on the LEFT, thumbs up on the RIGHT. Thumbs up = save it
//  (like a swipe right). Thumbs down = next song. Liquid Glass throughout
//  on watchOS 26+, graceful fallback below. Mirrors the iPhone's
//  light/dark theme.
//

import SwiftUI

/// Liquid Glass where available, invisible fallback elsewhere.
struct GlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 26, *) {
            content.glassEffect()
        } else {
            content
        }
    }
}

extension View {
    func liquidGlass() -> some View {
        modifier(GlassBackground())
    }
}

struct ContentView: View {
    @EnvironmentObject var bridge: WatchBridge

    var body: some View {
        VStack(spacing: 8) {
            // Mini player: artwork dot, track + artist, play/pause.
            if bridge.hasTrack {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .liquidGlass()
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(bridge.trackTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(bridge.trackArtist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { bridge.send(action: .togglePlay) } label: {
                        Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                            .frame(width: 38, height: 38)
                    }
                    .liquidGlass()
                    .clipShape(Circle())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Start discovering on iPhone")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            // Emoji thumbs: down on the left (skip), up on the right (save).
            HStack(spacing: 16) {
                Button { bridge.send(action: .thumbsDown) } label: {
                    Text("👎")
                        .font(.system(size: 30))
                        .frame(width: 64, height: 64)
                }
                .liquidGlass()
                .clipShape(Circle())
                .buttonStyle(.plain)
                .disabled(!bridge.hasTrack)

                Button { bridge.send(action: .thumbsUp) } label: {
                    Text("👍")
                        .font(.system(size: 30))
                        .frame(width: 64, height: 64)
                }
                .liquidGlass()
                .clipShape(Circle())
                .buttonStyle(.plain)
                .disabled(!bridge.hasTrack)
            }
            .padding(.top, 2)

            if let action = bridge.lastSentAction {
                Text(action == .thumbsUp ? "Saved ✓" : action == .thumbsDown ? "Skipped" : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .preferredColorScheme(bridge.theme == "light" ? .light : .dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchBridge())
}
