//
//  WatchBridge.swift
//  HiddenJams
//
//  iPhone side of the Apple Watch remote. Publishes the swipe deck's current
//  gem to the watch and receives thumbs up/down taps as player commands.
//  Thumbs up performs the exact same save as a swipe right (genre playlist
//  routing included); thumbs down skips.
//

import Foundation
import WatchConnectivity
import Combine

/// Wire format for watch -> iPhone actions. Must match `WatchAction` in the
/// watch app's WatchBridge.
enum WatchPlayerAction: String {
    case thumbsUp
    case thumbsDown
    case togglePlay
}

final class WatchBridge: NSObject, ObservableObject {
    static let shared = WatchBridge()

    /// Set by watch taps. PlaylistPlayerView observes this and performs the
    /// matching swipe (right for thumbs up, left for thumbs down).
    @Published var pendingCommand: WatchPlayerAction?

    private override init() { super.init() }

    private var cancellables = Set<AnyCancellable>()

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .notActivated else { return }
        session.delegate = self
        session.activate()
        // Mirror iOS theme changes to the watch.
        ThemeManager.shared.$mode
            .dropFirst()
            .sink { [weak self] _ in self?.pushTheme() }
            .store(in: &cancellables)
    }

    /// Pushes the deck's current gem to the watch. Pass nil fields to clear.
    /// Also carries playback state and the iOS app's theme so the watch
    /// mirrors both.
    func pushNowPlaying(title: String?, artist: String?, id: String?, isPlaying: Bool = false) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isPaired else { return }
        // Remember for theme re-pushes.
        lastTitle = title
        lastArtist = artist
        lastId = id
        lastIsPlaying = isPlaying
        var payload: [String: String] = [
            "theme": ThemeManager.shared.isLight ? "light" : "dark",
            "isPlaying": isPlaying ? "1" : "0",
        ]
        if let title, !title.isEmpty, let artist, let id {
            payload["title"] = title
            payload["artist"] = artist
            payload["id"] = id
        }
        sendContext(["nowPlaying": payload])
    }

    /// Pushes just the theme (called when the iOS theme changes) —
    /// re-sends the last track state so nothing is cleared.
    func pushTheme() {
        pushNowPlaying(
            title: lastTitle,
            artist: lastArtist,
            id: lastId,
            isPlaying: lastIsPlaying
        )
    }

    private var lastTitle: String?
    private var lastArtist: String?
    private var lastId: String?
    private var lastIsPlaying: Bool = false

    private func sendContext(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isPaired else { return }
        // Application context: always delivered, even if the watch app is
        // in the background.
        do {
            try session.updateApplicationContext(message)
        } catch {
            print("⌚️ Watch context update failed: \(error)")
        }
        // Immediate message too, so the foreground watch updates instantly.
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("⌚️ Watch message failed: \(error)")
            }
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error { print("⌚️ WCSession activation error: \(error)") }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS: re-activate after watch switches.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let raw = message["action"] as? String,
              let action = WatchPlayerAction(rawValue: raw) else { return }
        print("⌚️ Watch tapped: \(raw)")
        DispatchQueue.main.async { self.pendingCommand = action }
    }
}
