//
//  WatchBridge.swift
//  HiddenJamsWatch
//
//  Talks to the iPhone over WatchConnectivity: receives the now-playing gem
//  (title/artist) and sends thumbs up/down taps back as player commands.
//

import Foundation
import WatchConnectivity
import WatchKit
import Combine

/// Thumbs actions the watch can send. Raw values are the wire format —
/// they must match `WatchPlayerAction` in the iOS app's WatchBridge.
enum WatchAction: String {
    case thumbsUp
    case thumbsDown
    case togglePlay
    /// Build 78: open the current track in its source app on the iPhone
    /// (Spotify / Apple Music). Open only — nothing is liked or queued.
    case openInSource
}

final class WatchBridge: NSObject, ObservableObject {
    @Published var trackTitle: String = ""
    @Published var trackArtist: String = ""
    @Published var hasTrack = false
    @Published var isPlaying = false
    /// "light" or "dark" — mirrors the iOS app's theme.
    @Published var theme: String = "dark"
    /// Briefly shows a confirmation after a tap ("Saved ✓" / "Skipped").
    @Published var lastSentAction: WatchAction?
    /// Short confirmation after an "open in source" tap, e.g.
    /// "Opened in Spotify" or "Tap the alert on iPhone".
    @Published var openStatus: String?

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

    /// Tap on the artwork/title: ask the iPhone to open the current track in
    /// the app it came from. The phone replies with what it did so we can
    /// confirm with a haptic + a short label.
    func openInSourceApp() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        WKInterfaceDevice.current().play(.click)
        guard session.isReachable else {
            showOpenStatus("Open iPhone to connect", success: false)
            return
        }
        showOpenStatus("Opening…", success: nil)
        session.sendMessage(
            ["action": WatchAction.openInSource.rawValue],
            replyHandler: { [weak self] reply in
                let result = reply["result"] as? String ?? ""
                let service = reply["service"] as? String ?? ""
                let label: String
                var success = true
                switch result {
                case "opened": label = "Opened in \(service)"
                case "notified": label = "Tap the alert on iPhone"
                case "notificationsOff":
                    label = "Allow alerts in Hidden Jams"
                    success = false
                case "noLink":
                    label = "No link for this song"
                    success = false
                case "noTrack":
                    label = "Nothing playing"
                    success = false
                default:
                    label = "Couldn't reach iPhone"
                    success = false
                }
                DispatchQueue.main.async { self?.showOpenStatus(label, success: success) }
            },
            errorHandler: { [weak self] error in
                print("⌚️ openInSource failed: \(error)")
                DispatchQueue.main.async { self?.showOpenStatus("Couldn't reach iPhone", success: false) }
            }
        )
    }

    /// success: true → success haptic, false → failure haptic, nil → none.
    private func showOpenStatus(_ text: String, success: Bool?) {
        openStatus = text
        if let success {
            WKInterfaceDevice.current().play(success ? .success : .failure)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.openStatus == text { self?.openStatus = nil }
        }
    }

    private func applyTrackPayload(_ payload: Any?) {
        guard let dict = payload as? [String: String] else {
            DispatchQueue.main.async { self.hasTrack = false }
            return
        }
        // Theme and playback state ride along even when the track is cleared.
        let theme = dict["theme"]
        let isPlaying = dict["isPlaying"] == "1"
        guard let title = dict["title"], !title.isEmpty else {
            DispatchQueue.main.async {
                if let theme { self.theme = theme }
                self.isPlaying = isPlaying
                self.hasTrack = false
            }
            return
        }
        DispatchQueue.main.async {
            if let theme { self.theme = theme }
            self.isPlaying = isPlaying
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
