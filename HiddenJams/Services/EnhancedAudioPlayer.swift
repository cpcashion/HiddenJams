//
//  EnhancedAudioPlayer.swift
//  HiddenJams
//
//  Queue-based audio player for 30-second preview playlists
//

import Foundation
import AVFoundation
import Combine

class EnhancedAudioPlayer: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 30.0  // Always 30s for previews
    @Published var currentIndex: Int = 0
    @Published var currentTrackId: String? = nil
    @Published var playlist: [RecommendedTrack] = []
    
    @Published var hasPreview: Bool = false
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    
    init() {
        configureAudioSession()
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Queue Management
    
    func loadPlaylist(_ tracks: [RecommendedTrack]) {
        playlist = tracks
        currentIndex = 0
        
        if !playlist.isEmpty {
            playTrackAtIndex(0)
        }
    }
    
    func currentTrack() -> RecommendedTrack? {
        guard currentIndex < playlist.count else { return nil }
        return playlist[currentIndex]
    }
    
    // MARK: - Playback Controls
    
    func playTrackAtIndex(_ index: Int) {
        guard index >= 0 && index < playlist.count else {
            print("📭 No more tracks in playlist")
            isPlaying = false
            return
        }
        
        let track = playlist[index]
        currentIndex = index
        currentTrackId = track.id
        
        // Reset state
        cleanupObservers()
        currentTime = 0.0
        
        // Check if track has preview URL
        if let previewURLString = track.track.previewUrl,
           !previewURLString.isEmpty,
           let previewURL = URL(string: previewURLString) {
            
            hasPreview = true
            print("▶️ Playing: \(track.track.name) (\(currentIndex + 1)/\(playlist.count))")
            
            // Setup player
            let playerItem = AVPlayerItem(url: previewURL)
            player = AVPlayer(playerItem: playerItem)
            
            // Setup time observer
            let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                self?.currentTime = time.seconds
            }
            
            // Setup end observer
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                self?.handleTrackEnded()
            }
            
            // Start playback
            player?.play()
            isPlaying = true
            
        } else {
            // No preview available - show card but don't play
            print("⚠️ No preview for: \(track.track.name) - Showing card anyway")
            hasPreview = false
            isPlaying = false
            player = nil
        }
    }
    
    func play() {
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func playNext() {
        let nextIndex = currentIndex + 1
        if nextIndex < playlist.count {
            playTrackAtIndex(nextIndex)
        } else {
            // End of playlist
            pause()
            print("🎉 Playlist complete!")
        }
    }
    
    func playPrevious() {
        // If more than 3 seconds in, restart current track
        if currentTime > 3.0 {
            player?.seek(to: .zero)
            currentTime = 0.0
        } else {
            // Go to previous track
            let prevIndex = currentIndex - 1
            if prevIndex >= 0 {
                playTrackAtIndex(prevIndex)
            }
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    // MARK: - Private
    
    private func handleTrackEnded() {
        print("✅ Track ended, auto-advancing...")
        playNext()
    }
    
    private func cleanupObservers() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }
    
    deinit {
        cleanupObservers()
    }
}
