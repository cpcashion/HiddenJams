//
//  SourceAppOpener.swift
//  HiddenJams
//
//  Build 78: "tap the watch, open the song". A tap on the artwork/title in
//  the Apple Watch Now Playing screen (or the watchOS double-tap gesture)
//  asks the iPhone to open the current track in the app it came from —
//  Spotify (spotify:track:ID, falling back to open.spotify.com) or Apple
//  Music (the track's store URL) — via FullSongOpener's existing resolver.
//
//  It ONLY opens the song. It never adds anything to Spotify Liked Songs,
//  never queues anything in Spotify, and never touches a playlist.
//
//  iOS won't let a backgrounded app (or a locked phone) bring another app
//  to the foreground, so:
//    • iPhone app active  → open the track in its source app right away.
//    • otherwise          → post a time-sensitive local notification
//                           "Open '<track>' in Spotify"; tapping it opens
//                           the track.
//  Either way the track is also published as an NSUserActivity (web URL)
//  so Handoff can offer it on the user's other devices.
//

import UIKit
import UserNotifications

final class SourceAppOpener: NSObject {
    static let shared = SourceAppOpener()

    /// Returns the track that's currently loaded in the player. Wired up by
    /// ContentView (which owns the live AudioPreviewManager).
    var currentTrackProvider: (() -> RecommendedTrack?)?

    /// Outcome reported back to the watch for its confirmation label.
    enum Outcome {
        case opened(service: String)
        case notified(service: String)
        case notificationsOff(service: String)
        case noLink
        case noTrack

        /// Short wire value for the watch.
        var code: String {
            switch self {
            case .opened: return "opened"
            case .notified: return "notified"
            case .notificationsOff: return "notificationsOff"
            case .noLink: return "noLink"
            case .noTrack: return "noTrack"
            }
        }

        var serviceName: String {
            switch self {
            case .opened(let s), .notified(let s), .notificationsOff(let s): return s
            case .noLink, .noTrack: return ""
            }
        }
    }

    static let categoryIdentifier = "HJ_OPEN_IN_SOURCE"
    private static let requestIdentifier = "hj.openInSource"
    private static let askedKey = "hiddenjams_open_in_source_notif_asked"

    /// Retained so Handoff keeps advertising the current track.
    private var handoffActivity: NSUserActivity?

    private override init() { super.init() }

    // MARK: - Setup

    /// Installs the notification delegate so a tap on the "Open in …" alert
    /// opens the track. Call once at launch.
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Graceful permission ask: only once, only while the app is in the
    /// foreground, and only for people who actually use the watch app.
    /// Called by WatchBridge when it sees a paired watch with the app.
    func requestNotificationPermissionIfNeeded() {
        guard UIApplication.shared.applicationState == .active else { return }
        guard !UserDefaults.standard.bool(forKey: Self.askedKey) else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                print("🔔 Open-in-source notifications \(granted ? "allowed" : "declined")")
            } catch {
                print("🔔 Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Open

    /// Opens (or offers to open) the current track in its source app.
    /// Completion is called on the main actor.
    func openCurrentTrack(completion: @escaping (Outcome) -> Void) {
        guard let track = currentTrackProvider?() else {
            completion(.noTrack)
            return
        }
        guard let service = FullSongOpener.service(for: track) else {
            completion(.noLink)
            return
        }
        let serviceName = service.displayName
        publishHandoff(track: track, service: service)

        if UIApplication.shared.applicationState == .active {
            FullSongOpener.open(service)
            completion(.opened(service: serviceName))
            return
        }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                await postOpenNotification(track: track, service: service)
                completion(.notified(service: serviceName))
            default:
                completion(.notificationsOff(service: serviceName))
            }
        }
    }

    private func postOpenNotification(track: RecommendedTrack, service: FullSongOpener.Service) async {
        let content = UNMutableNotificationContent()
        content.title = "Open “\(track.track.name)” in \(service.displayName)"
        content.body = "\(track.track.artistNames) · Tap to open"
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        // Time-sensitive breaks through Focus only if the app carries the
        // time-sensitive entitlement; without it iOS delivers it as a normal
        // (active) alert, which is fine.
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        content.userInfo = Self.userInfo(for: service)

        // One pending "open" alert at a time — replace the previous one.
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestIdentifier])
        let request = UNNotificationRequest(identifier: Self.requestIdentifier, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            print("🔔 Open-in-source notification failed: \(error)")
        }
    }

    // MARK: - Handoff

    private func publishHandoff(track: RecommendedTrack, service: FullSongOpener.Service) {
        guard let url = Self.webURL(for: service) else { return }
        let activity = handoffActivity ?? NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.title = "\(track.track.name) — \(track.track.artistNames)"
        activity.webpageURL = url
        activity.isEligibleForHandoff = true
        activity.becomeCurrent()
        handoffActivity = activity
    }

    // MARK: - Encoding

    private static func userInfo(for service: FullSongOpener.Service) -> [String: String] {
        switch service {
        case .spotify(let trackId): return ["service": "spotify", "trackId": trackId]
        case .appleMusic(let url): return ["service": "appleMusic", "url": url.absoluteString]
        }
    }

    private static func service(from userInfo: [AnyHashable: Any]) -> FullSongOpener.Service? {
        switch userInfo["service"] as? String {
        case "spotify":
            guard let id = userInfo["trackId"] as? String, !id.isEmpty else { return nil }
            return .spotify(trackId: id)
        case "appleMusic":
            guard let raw = userInfo["url"] as? String, let url = URL(string: raw) else { return nil }
            return .appleMusic(url: url)
        default:
            return nil
        }
    }

    static func webURL(for service: FullSongOpener.Service) -> URL? {
        switch service {
        case .spotify(let trackId): return URL(string: "https://open.spotify.com/track/\(trackId)")
        case .appleMusic(let url): return url
        }
    }
}

// MARK: - Notification tap → open the track

extension SourceAppOpener: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        if content.categoryIdentifier == Self.categoryIdentifier,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let service = Self.service(from: content.userInfo) {
            // The tap launches/foregrounds Hidden Jams; hand straight off to
            // the source app once we're active.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                FullSongOpener.open(service)
            }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
