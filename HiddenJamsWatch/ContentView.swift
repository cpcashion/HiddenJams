//
//  ContentView.swift
//  HiddenJamsWatch
//
//  Now-playing gem on top, thumbs down on the LEFT, thumbs up on the RIGHT.
//  Thumbs up = save it (like a swipe right). Thumbs down = next song.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bridge: WatchBridge

    var body: some View {
        VStack(spacing: 6) {
            if bridge.hasTrack {
                Text(bridge.trackTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(bridge.trackArtist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Start discovering on iPhone")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                // LEFT: thumbs down = skip to the next song.
                Button { bridge.send(action: .thumbsDown) } label: {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.system(size: 26))
                        .frame(width: 62, height: 62)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
                .disabled(!bridge.hasTrack)

                // RIGHT: thumbs up = save the song.
                Button { bridge.send(action: .thumbsUp) } label: {
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 26))
                        .frame(width: 62, height: 62)
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
                .disabled(!bridge.hasTrack)
            }
            .padding(.top, 2)

            if let action = bridge.lastSentAction {
                Text(action == .thumbsUp ? "Saved ✓" : "Skipped")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchBridge())
}
