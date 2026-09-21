//
//  AudioPreviewManager.swift
//  HiddenJams
//
//  Manages 30-second audio preview playback
//

import Foundation
import AVFoundation
import Combine

class AudioPreviewManager: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrackId: String?
    @Published var queue: [RecommendedTrack] = []
    @Published var currentIndex: Int = 0
    @Published var currentTrack: RecommendedTrack?
    @Published var hasPreview: Bool = false
    @Published var currentTime: Double = 0.0
    @Published var duration: Double = 30.0
    
    // Legacy support alias
    var playlist: [RecommendedTrack] { queue }
    
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
    
    func loadQueue(_ tracks: [RecommendedTrack], autoPlay: Bool = true) {
        queue = tracks
        currentIndex = 0
        if autoPlay && !queue.isEmpty {
            playTrackAtIndex(0)
        }
    }
    
    func playTrackAtIndex(_ index: Int) {
        guard index >= 0 && index < queue.count else { return }
        
        let track = queue[index]
        currentIndex = index
        currentTrack = track
        
        stop() // Stops current player and observers
        
        if let previewUrl = track.track.previewUrl, !previewUrl.isEmpty {
             hasPreview = true
             playPreview(url: previewUrl, trackId: track.id)
        } else {
             hasPreview = false
             print("⚠️ No preview URL for \(track.track.name)")
             // Do not autoplay next immediately? Or show card?
             // EnhancedAudioPlayer showed card but didn't play.
             // We'll set isPlaying = false
             isPlaying = false
        }
    }
    
    func playNext() {
        let nextIndex = currentIndex + 1
        if nextIndex < queue.count {
            playTrackAtIndex(nextIndex)
        } else {
            stop()
        }
    }
    
    func playPrevious() {
        if currentTime > 3.0 {
            player?.seek(to: .zero)
            currentTime = 0.0
        } else {
            let prevIndex = currentIndex - 1
            if prevIndex >= 0 {
                playTrackAtIndex(prevIndex)
            }
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }
    
    func playTrack(_ track: RecommendedTrack) {
        if let index = queue.firstIndex(where: { $0.id == track.id }) {
            playTrackAtIndex(index)
        } else {
            // If not in queue, just play it standalone?
            // Or add to queue? Let's treat it as standalone for now or replace queue.
            // For safety, replace queue with single track
            loadQueue([track])
        }
    }
    
    func playPreview(url: String, trackId: String) {
        if currentTrackId != trackId {
             stop()
        }
        
        guard let previewURL = URL(string: url) else { return }
        
        // Create player
        let playerItem = AVPlayerItem(url: previewURL)
        player = AVPlayer(playerItem: playerItem)
        currentTrackId = trackId
        
        // Add time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
             self?.currentTime = time.seconds
        }
        
        // End observer
        endObserver = NotificationCenter.default.addObserver(
             forName: .AVPlayerItemDidPlayToEndTime,
             object: playerItem,
             queue: .main
        ) { [weak self] _ in
             self?.playNext()
        }
        
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func resume() {
        player?.play()
        isPlaying = true
    }
    
    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }
    
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        // Do not clear currentTrack/currentIndex here, just stop playback?
        // If we clear currentTrack, the miniplayer disappears.
        // So just stop audio.
        currentTime = 0.0
        
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }
    
    @objc private func playerDidFinish() {
        playNext()
    }
    
    deinit {
        stop()
    }
}
