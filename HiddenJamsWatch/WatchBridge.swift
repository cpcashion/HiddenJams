//
//  WatchBridge.swift
//  HiddenJamsWatch
//
//  Talks to the iPhone over WatchConnectivity: receives the now-playing gem
//  (title/artist) and sends thumbs up/down taps back as player commands.
//

import Foundation
import WatchConnectivity
import Combine

/// Thumbs actions the watch can send. Raw values are the wire format —
/// they must match `WatchPlayerAction` in the iOS app's WatchBridge.
enum WatchAction: String {
    case thumbsUp
    case thumbsDown
}

final class WatchBridge: NSObject, ObservableObject {
    @Published var trackTitle: String = ""
    @Published var trackArtist: String = ""
    @Published var hasTrack = false
    /// Briefly shows a confirmation after a tap ("Saved ✓" / "Skipped").
    @Published var lastSentAction: WatchAction?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(action: WatchAction) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.sendMessage(["action": action.rawValue], replyHandler: nil) { error in
            print("⌚️ sendMessage failed: \(error)")
        }
        lastSentAction = action
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.lastSentAction == action { self?.lastSentAction = nil }
        }
    }

    private func applyTrackPayload(_ payload: Any?) {
        guard let dict = payload as? [String: String],
              let title = dict["title"], !title.isEmpty else {
            DispatchQueue.main.async { self.hasTrack = false }
            return
        }
        DispatchQueue.main.async {
            self.trackTitle = title
            self.trackArtist = dict["artist"] ?? ""
            self.hasTrack = true
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error { print("⌚️ activation error: \(error)") }
        // Pick up any now-playing state delivered while we were inactive.
        applyTrackPayload(session.receivedApplicationContext["nowPlaying"])
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        applyTrackPayload(applicationContext["nowPlaying"])
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        // The iPhone also pushes the track via sendMessage when the watch
        // app is in the foreground — accept both paths.
        if message["nowPlaying"] != nil {
            applyTrackPayload(message["nowPlaying"])
        }
    }
}
