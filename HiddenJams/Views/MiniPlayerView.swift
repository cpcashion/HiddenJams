import SwiftUI

struct MiniPlayerView: View {
    let track: RecommendedTrack
    let isPlaying: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onMaximize: () -> Void
    
    var body: some View {
        Button(action: onMaximize) {
            HStack(spacing: Theme.Spacing.md) {
                // Album Art
                AsyncImage(url: track.track.album.albumArtURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Theme.Colors.spotifyDarkGray)
                }
                .frame(width: 40, height: 40)
                .cornerRadius(Theme.CornerRadius.sm)
                
                // Track Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.track.name)
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(track.track.artistNames)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Play/Pause Button
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(8)
                }
                
                // Next Button
                Button(action: onNext) {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(8)
                }
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                    .fill(Theme.Colors.cardGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.lg) // Safe area padding
        }
        .buttonStyle(PlainButtonStyle())
    }
}
