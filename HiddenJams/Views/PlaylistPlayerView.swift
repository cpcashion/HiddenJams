//
//  PlaylistPlayerView.swift
//  HiddenJams
//
//  Premium stacked card player - swipe right to like, left to skip
//

import SwiftUI
import UIKit

struct PlaylistPlayerView: View {
    @EnvironmentObject var audioPlayer: AudioPreviewManager
    @Environment(\.dismiss) var dismiss
    
    let recommendations: [RecommendedTrack]
    let onSave: (RecommendedTrack) -> Void
    var onMinimize: (() -> Void)? = nil
    var onDiscoverMore: (() -> Void)? = nil
    var isRefreshing: Bool = false
    var refreshProgress: String = ""
    
    @State private var savedTracks: Set<String> = []
    @State private var isDraggingTime = false
    @State private var dragTime: Double = 0.0
    
    // Card swipe state
    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var cardOpacity: Double = 1.0
    @State private var cardScale: Double = 1.0
    @State private var isAnimatingOut = false
    
    // Swipe thresholds
    private let swipeThreshold: CGFloat = 100
    private let maxRotation: Double = 5
    
    private var currentTrack: RecommendedTrack? {
        audioPlayer.currentTrack
    }
    
    // Get visible tracks for the stack (current + next)
    private var visibleTracks: [RecommendedTrack] {
        var tracks: [RecommendedTrack] = []
        let currentIdx = audioPlayer.currentIndex
        
        // Add next track first (it renders behind)
        if currentIdx + 1 < audioPlayer.queue.count {
            tracks.append(audioPlayer.queue[currentIdx + 1])
        }
        // Add current track last (it renders on top)
        if currentIdx < audioPlayer.queue.count {
            tracks.append(audioPlayer.queue[currentIdx])
        }
        return tracks
    }
    
    var body: some View {
        ZStack {
            Theme.Colors.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                header
                
                Spacer()
                
                // Card Stack
                if let track = currentTrack {
                    cardStack(track)
                } else {
                    emptyState
                }
                
                Spacer()
                
                // Progress & Controls
                controlsSection
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, 120)
            }
            
            // Full-screen discovery loading overlay
            if isRefreshing {
                DiscoveryLoadingView(progressMessage: refreshProgress)
                    .transition(.opacity)
            }
        }
        .onAppear {
            let currentIDs = audioPlayer.queue.map { $0.id }
            let newIDs = recommendations.map { $0.id }
            
            if currentIDs != newIDs {
                audioPlayer.loadQueue(recommendations)
            }
        }
        .onChange(of: recommendations.count) { newCount in
            print("🔄 Recommendations count changed to \(newCount), reloading queue...")
            audioPlayer.loadQueue(recommendations)
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: { 
                if let onMinimize = onMinimize {
                    onMinimize()
                } else {
                    dismiss() 
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("Hidden Jams")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("Track \(audioPlayer.currentIndex + 1) of \(recommendations.count)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            Spacer()
            
            // Placeholder for balance
            Image(systemName: "chevron.down")
                .font(.title2)
                .foregroundColor(.clear)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, 60)
        .padding(.bottom, Theme.Spacing.md)
    }
    
    // MARK: - Card Stack
    
    private func cardStack(_ track: RecommendedTrack) -> some View {
        ZStack(alignment: .top) {
            // Render cards from back to front using visibleTracks
            ForEach(visibleTracks, id: \.id) { cardTrack in
                let isCurrentCard = cardTrack.id == track.id
                let isNextCard = !isCurrentCard
                
                cardView(for: cardTrack, isCurrentCard: isCurrentCard)
                    // Only apply swipe transforms to the current (front) card
                    .scaleEffect(isCurrentCard ? cardScale : 0.95)
                    .offset(x: isCurrentCard ? cardOffset.width : 0, y: 0)
                    .rotationEffect(.degrees(isCurrentCard ? cardRotation : 0))
                    .opacity(isCurrentCard ? cardOpacity : (isNextCard ? 1.0 : 0))
                    .zIndex(isCurrentCard ? 1 : 0)
                    .allowsHitTesting(isCurrentCard)
                    // Smooth spring animation for when next card becomes current
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isCurrentCard)
                    .gesture(
                        isCurrentCard ?
                        DragGesture()
                            .onChanged(onDragChanged)
                            .onEnded(onDragEnded)
                        : nil
                    )
            }
            
            // Refresh button behind the last card when there's no next track
            if visibleTracks.count == 1 {
                refreshRevealView
                    .opacity(1.0 - cardOpacity) // Reveals as current card fades
                    .zIndex(-1)
            }
        }
    }
    
    // Single card view with album art and text
    private func cardView(for track: RecommendedTrack, isCurrentCard: Bool) -> some View {
        VStack(spacing: 12) {
            // Album Art with overlays
            ZStack {
                AsyncImage(url: track.track.album.albumArtURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Theme.Colors.spotifyDarkGray)
                }
                .frame(width: 320, height: 320)
                .cornerRadius(Theme.CornerRadius.lg)
                
                // Only show overlays on current card being swiped
                if isCurrentCard {
                    likeOverlay
                    skipOverlay
                }
            }
            .applyShadow(Theme.Shadows.large)
            
            // Track Info - ONLY show for current card to prevent overlap
            if isCurrentCard {
                VStack(spacing: 6) {
                    // Tappable song title - opens track in Spotify
                    Text(track.track.name)
                        .font(Theme.Typography.title)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .onTapGesture {
                            openSpotifyTrack(id: track.id)
                        }
                    
                    // Tappable artist name - opens first artist in Spotify
                    Text(track.track.artistNames)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .onTapGesture {
                            if let firstArtist = track.track.artists.first {
                                openSpotifyArtist(id: firstArtist.id)
                            }
                        }
                }
                .padding(.top, 32)
                .padding(.horizontal, Theme.Spacing.md)
            }
        }
    }
    
    // Refresh button that appears behind the last card
    private var refreshRevealView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(Theme.Colors.spotifyGreen)
            
            Text("Discover More")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Button(action: {
                if let onDiscoverMore = onDiscoverMore {
                    onDiscoverMore()
                }
            }) {
                Text("Refresh")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .frame(width: 200)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Theme.Colors.accentPurple.opacity(0.5), Theme.Colors.accentPink.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(Theme.CornerRadius.md)
            }
        }
        .frame(width: 320, height: 320)
        .background(Theme.Colors.spotifyDarkGray.opacity(0.3))
        .cornerRadius(Theme.CornerRadius.lg)
    }
    
    // MARK: - Overlays
    
    private var likeOverlay: some View {
        Group {
            if cardOffset.width > 30 {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .fill(Theme.Colors.gemGold.opacity(0.5))
                    
                    VStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 44, weight: .medium))
                            .foregroundColor(.white)
                        Text("LIKE")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 320, height: 320)
                .opacity(min(Double(cardOffset.width) / 100, 1.0))
            }
        }
    }
    
    private var skipOverlay: some View {
        Group {
            if cardOffset.width < -30 {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.lg)
                        .fill(Color.red.opacity(0.5))
                    
                    VStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                        Text("SKIP")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 320, height: 320)
                .opacity(min(Double(-cardOffset.width) / 100, 1.0))
            }
        }
    }
    
    // MARK: - Gesture Handlers
    
    private func onDragChanged(_ gesture: DragGesture.Value) {
        guard !isAnimatingOut else { return }
        
        // Horizontal-only card movement
        cardOffset = CGSize(width: gesture.translation.width, height: 0)
        
        // Subtle rotation
        let rotationAmount = gesture.translation.width / 40
        cardRotation = min(max(rotationAmount, -maxRotation), maxRotation)
        
        // Progressive fade as card moves off screen
        let dragDistance = abs(gesture.translation.width)
        let fadeStart: CGFloat = 120
        if dragDistance > fadeStart {
            cardOpacity = max(0.2, 1.0 - Double((dragDistance - fadeStart) / 150))
        } else {
            cardOpacity = 1.0
        }
        
        // Minimal scale reduction
        let scaleReduction = min(dragDistance / 1000, 0.03)
        cardScale = 1.0 - scaleReduction
    }
    
    private func onDragEnded(_ gesture: DragGesture.Value) {
        guard !isAnimatingOut else { return }
        
        let velocity = gesture.predictedEndLocation.x - gesture.location.x
        let width = gesture.translation.width
        
        // Use velocity to make throwing feel more natural
        let shouldSwipeRight = width > swipeThreshold || (width > 40 && velocity > 200)
        let shouldSwipeLeft = width < -swipeThreshold || (width < -40 && velocity < -200)
        
        if shouldSwipeRight {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            swipeCardOff(direction: .right)
        } else if shouldSwipeLeft {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            swipeCardOff(direction: .left)
        } else {
            // Snap back to center
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                cardOffset = .zero
                cardRotation = 0
                cardOpacity = 1.0
                cardScale = 1.0
            }
        }
    }
    
    private enum SwipeDirection {
        case left, right
    }
    
    private func swipeCardOff(direction: SwipeDirection) {
        isAnimatingOut = true
        
        let screenWidth = UIScreen.main.bounds.width
        let exitOffset: CGFloat = direction == .right ? screenWidth + 100 : -screenWidth - 100
        let exitRotation: Double = direction == .right ? 8 : -8
        
        // Animate current card off screen
        withAnimation(.easeOut(duration: 0.3)) {
            cardOffset = CGSize(width: exitOffset, height: 0)
            cardRotation = exitRotation
            cardOpacity = 0
            cardScale = 0.95
        }
        
        // After animation completes, update state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Handle like/skip action
            if direction == .right, let track = currentTrack {
                savedTracks.insert(track.id)
                onSave(track)
            }
            
            // Check if there's a next track
            let hasNextTrack = audioPlayer.currentIndex + 1 < audioPlayer.queue.count
            
            isAnimatingOut = false
            
            if hasNextTrack {
                // Reset card state for the new current card
                cardOffset = .zero
                cardRotation = 0
                cardOpacity = 1.0
                cardScale = 1.0
                
                // Move to next track
                audioPlayer.playNext()
            } else {
                // Last track - DON'T reset card state, keep it off-screen
                // so the refresh button stays visible
                audioPlayer.playNext()
            }
        }
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Progress Bar
            progressBar
                .padding(.horizontal, Theme.Spacing.md)
            
            // Swipe hints - subtle, not like buttons
            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "arrow.left")
                    Text("Skip")
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Color.white.opacity(0.25)) // Much darker
                
                Spacer()
                
                // Play/Pause
                Button(action: { audioPlayer.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(audioPlayer.hasPreview ? Theme.Colors.spotifyGreen : Color.gray.opacity(0.5))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .disabled(!audioPlayer.hasPreview)
                
                Spacer()
                
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Like")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Color.white.opacity(0.25)) // Much darker
            }
            .padding(.horizontal, Theme.Spacing.xl)
            
            // Open in Spotify (if no preview)
            if !audioPlayer.hasPreview, let track = currentTrack {
                Button(action: {
                    if let url = URL(string: "https://open.spotify.com/track/\(track.id)") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.right.circle.fill")
                        Text("Open in Spotify")
                    }
                    .font(Theme.Typography.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.spotifyGreen)
                    .cornerRadius(Theme.CornerRadius.circle)
                }
            }
            // Refresh button removed - shown in empty state only
        }
    }
    
    private var progressBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if audioPlayer.hasPreview {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background Track
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 4)
                        
                        // Active Progress
                        Rectangle()
                            .fill(Theme.Colors.spotifyGreen)
                            .frame(
                                width: geometry.size.width * (CGFloat(isDraggingTime ? dragTime : audioPlayer.currentTime) / 30.0),
                                height: 4
                            )
                        
                        // Scrubber Knob
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .offset(x: (geometry.size.width * (CGFloat(isDraggingTime ? dragTime : audioPlayer.currentTime) / 30.0)) - 6)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingTime = true
                                let pct = min(max(0, value.location.x / geometry.size.width), 1)
                                dragTime = Double(pct) * 30.0
                            }
                            .onEnded { value in
                                let pct = min(max(0, value.location.x / geometry.size.width), 1)
                                let finalTime = Double(pct) * 30.0
                                audioPlayer.seek(to: finalTime)
                                isDraggingTime = false
                            }
                    )
                }
                .frame(height: 12)
                
                HStack {
                    Text(formatTime(isDraggingTime ? dragTime : audioPlayer.currentTime))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                    
                    Spacer()
                    
                    Text(formatTime(30.0))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            } else {
                Text("Preview Unavailable")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(Theme.Colors.spotifyGreen)
            
            Text("You've Listened to Everything!")
                .font(Theme.Typography.title)
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text("Listened to \(recommendations.count) tracks")
                .font(Theme.Typography.body2)
                .foregroundColor(Theme.Colors.textSecondary)
            
            // Refresh button - revealed after all songs
            Button(action: {
                if let onDiscoverMore = onDiscoverMore {
                    onDiscoverMore()
                }
            }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Refresh")
                }
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Theme.Colors.accentPurple.opacity(0.4), Theme.Colors.accentPink.opacity(0.4)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(Theme.CornerRadius.md)
            }
            .padding(.top, Theme.Spacing.md)
        }
        .padding(Theme.Spacing.xl)
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    // MARK: - Spotify Deep Links
    
    private func openSpotifyTrack(id: String) {
        // Try Spotify app deep link first, falls back to web
        let spotifyAppURL = URL(string: "spotify:track:\(id)")
        let webURL = URL(string: "https://open.spotify.com/track/\(id)")
        
        if let appURL = spotifyAppURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = webURL {
            UIApplication.shared.open(webURL)
        }
    }
    
    private func openSpotifyArtist(id: String) {
        // Try Spotify app deep link first, falls back to web
        let spotifyAppURL = URL(string: "spotify:artist:\(id)")
        let webURL = URL(string: "https://open.spotify.com/artist/\(id)")
        
        if let appURL = spotifyAppURL, UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = webURL {
            UIApplication.shared.open(webURL)
        }
    }
}
