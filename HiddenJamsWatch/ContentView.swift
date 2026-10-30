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
//  Layout is overflow-safe: compact player, fixed thumb sizes, spacers
//  absorb extra space so nothing overlaps on 40mm screens.
//

import SwiftUI

/// Liquid Glass where available, invisible fallback elsewhere.
/// Applied AFTER clipShape so the glass follows the clipped shape.
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
        VStack(spacing: 6) {
            // Mini player: artwork dot, track + artist, play/pause.
            // Compact fixed height so it never pushes the thumbs around.
            if bridge.hasTrack {
                HStack(spacing: 8) {
                    Image(systemName: "music.note")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                        .liquidGlass()

                    VStack(alignment: .leading, spacing: 1) {
                        Text(bridge.trackTitle)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(bridge.trackArtist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button { bridge.send(action: .togglePlay) } label: {
                        // Lime play disc (build 76 redesign — matches iPhone).
                        Image(systemName: bridge.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(red: 0.043, green: 0.043, blue: 0.059))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Self.lime))
                    }
                    .clipShape(Circle())
                    .buttonStyle(.plain)
                }
                .frame(height: 44)
                .padding(.horizontal, 4)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Start discovering on iPhone")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 44)
            }

            Spacer(minLength: 2)

            // Emoji thumbs: down on the LEFT (skip), up on the RIGHT (save).
            // Fixed 60pt targets with breathing room — never overlapping.
            HStack(spacing: 20) {
                Button { bridge.send(action: .thumbsDown) } label: {
                    Text("👎")
                        .font(.system(size: 28))
                        .frame(width: 60, height: 60)
                }
                .clipShape(Circle())
                .liquidGlass()
                .buttonStyle(.plain)
                .disabled(!bridge.hasTrack)

                Button { bridge.send(action: .thumbsUp) } label: {
                    Text("👍")
                        .font(.system(size: 28))
                        .frame(width: 60, height: 60)
                }
                .clipShape(Circle())
                .liquidGlass()
                .buttonStyle(.plain)
                .disabled(!bridge.hasTrack)
            }

            // Status line: fixed height so it never shifts the thumbs.
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(height: 16)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ambientBackground.ignoresSafeArea())
        .preferredColorScheme(bridge.theme == "light" ? .light : .dark)
    }

    // MARK: - Build 76 palette (near-black + plum glow, lime accent)

    static let lime = Color(red: 0xC8 / 255, green: 0xE8 / 255, blue: 0x6B / 255)

    /// Plum → near-black with a soft magenta bloom (warm paper in light mode).
    private var ambientBackground: some View {
        let light = bridge.theme == "light"
        return ZStack {
            LinearGradient(
                colors: light
                    ? [Color(red: 0.984, green: 0.965, blue: 0.941), Color(red: 0.969, green: 0.953, blue: 0.933)]
                    : [Color(red: 0.110, green: 0.063, blue: 0.141), Color(red: 0.043, green: 0.043, blue: 0.059)],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    (light ? Color(red: 0.976, green: 0.788, blue: 0.659) : Color(red: 0.878, green: 0.337, blue: 0.710)).opacity(light ? 0.45 : 0.35),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 140
            )
        }
    }

    private var statusText: String {
        guard let action = bridge.lastSentAction else { return "" }
        switch action {
        case .thumbsUp: return "Saved ✓"
        case .thumbsDown: return "Skipped"
        default: return ""
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchBridge())
}
