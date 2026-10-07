//
//  SpotifyFullSongService.swift
//  HiddenJams
//
//  In-app full-song playback for Spotify Premium users via the Spotify
//  iOS SDK App Remote. Plays the full track inside Hidden Jams — the user
//  never leaves the app. Requires the Spotify app installed + Premium.
//

import Foundation
import Combine
import SpotifyiOS

@MainActor
class SpotifyFullSongService: NSObject, ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var isConnected: Bool = false

    var onEnded: (() -> Void)?

    private static let clientID = "d5baa23332d64e198419d95d2272be2e"
    private static let redirectURI = URL(string: "spotifyhiddengems://callback")!

    private lazy var appRemote: SPTAppRemote = {
        let configuration = SPTConfiguration(
            clientID: Self.clientID,
            redirectURL: Self.redirectURI
        )
        let remote = SPTAppRemote(configuration: configuration, logLevel: .none)
        remote.delegate = self
        return remote
    }()

    private var pollTimer: Timer?
    private var currentURI: String?
    /// True while we're waiting for the Spotify app to call back from an
    /// App Remote auth. Only then should onOpenURL route to the SDK —
    /// otherwise the URL belongs to the web-API (PKCE) login flow.
    /// Lock-protected so handleRedirect can stay nonisolated (onOpenURL
    /// is synchronous and must not hop actors).
    private let authFlagLock = NSLock()
    private var _awaitingAuthCallback = false
    private var awaitingAuthCallback: Bool {
        get { authFlagLock.withLock { _awaitingAuthCallback } }
        set { authFlagLock.withLock { _awaitingAuthCallback = newValue } }
    }

    /// True when the Spotify app is installed (App Remote requires it).
    var isSpotifyAppInstalled: Bool {
        guard let url = URL(string: "spotify:") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Connects the App Remote (authenticates through the Spotify app).
    /// Calls completion with true when the connection is established.
    func connect() async -> Bool {
        if appRemote.isConnected { return true }
        guard isSpotifyAppInstalled else { return false }
        return await withCheckedContinuation { continuation in
            var resumed = false
            self.pendingConnectContinuation = { success in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: success)
            }
            self.awaitingAuthCallback = true
            // Safety timeout — don't hang forever if the Spotify app
            // never calls back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self, !resumed else { return }
                resumed = true
                self.pendingConnectContinuation = nil
                self.awaitingAuthCallback = false
                continuation.resume(returning: self.appRemote.isConnected)
            }
            self.appRemote.authorizeAndPlayURI("", scope: [.appRemoteControl]) { [weak self] error in
                if let error {
                    print("⚠️ Spotify App Remote auth error: \(error)")
                    self?.pendingConnectContinuation?(false)
                    self?.pendingConnectContinuation = nil
                }
                // Success arrives via appRemoteDidEstablishConnection.
            }
        }
    }

    private var pendingConnectContinuation: ((Bool) -> Void)?

    /// Routes the OAuth callback URL to the SDK. Call from the app's
    /// onOpenURL handler. Returns true only when we're actually waiting
    /// for an App Remote auth callback — otherwise the URL belongs to
    /// the web-API (PKCE) login flow and must pass through.
    nonisolated func handleRedirect(url: URL) -> Bool {
        guard awaitingAuthCallback,
              url.scheme == "spotifyhiddengems" else { return false }
        awaitingAuthCallback = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Per Spotify's docs: extract the access token from the
            // callback and hand it to the remote; the delegate then
            // reports the established connection.
            if let params = self.appRemote.authorizationParameters(from: url),
               let token = params[SPTAppRemoteAccessTokenKey] {
                self.appRemote.connectionParameters.accessToken = token
            } else {
                // No token — auth failed or was cancelled.
                self.pendingConnectContinuation?(false)
                self.pendingConnectContinuation = nil
            }
        }
        return true
    }

    func play(uri: String) async -> Bool {
        guard await connect() else { return false }
        currentURI = uri
        return await withCheckedContinuation { continuation in
            appRemote.playerAPI?.play(uri) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        print("⚠️ Spotify play failed: \(error)")
                        continuation.resume(returning: false)
                    } else {
                        self?.isPlaying = true
                        self?.startPolling()
                        continuation.resume(returning: true)
                    }
                }
            }
        }
    }

    func pause() {
        appRemote.playerAPI?.pause { [weak self] _, _ in
            Task { @MainActor in self?.isPlaying = false }
        }
    }

    func resume() {
        appRemote.playerAPI?.resume { [weak self] _, _ in
            Task { @MainActor in self?.isPlaying = true }
        }
    }

    func seek(to seconds: Double) {
        let ms = Int(seconds * 1000)
        appRemote.playerAPI?.seek(toPosition: ms) { [weak self] _, _ in
            Task { @MainActor in self?.position = seconds }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        appRemote.playerAPI?.pause(nil)
        isPlaying = false
        position = 0
        duration = 0
        currentURI = nil
    }

    func disconnect() {
        stop()
        if appRemote.isConnected {
            appRemote.disconnect()
        }
        isConnected = false
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refreshState()
        }
    }

    private func refreshState() {
        appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
            guard let self,
                  let state = result as? SPTAppRemotePlayerState else { return }
            Task { @MainActor in
                self.position = Double(state.playbackPosition) / 1000.0
                self.duration = Double(state.track.duration) / 1000.0
                let wasPlaying = self.isPlaying
                self.isPlaying = !state.isPaused
                // Natural end: was playing, now paused at the very end.
                if wasPlaying, state.isPaused,
                   self.duration > 0,
                   self.position >= self.duration - 1.5 {
                    let cb = self.onEnded
                    self.stop()
                    cb?()
                }
            }
        }
    }
}

// MARK: - SPTAppRemoteDelegate

extension SpotifyFullSongService: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            self.isConnected = true
            self.awaitingAuthCallback = false
            self.pendingConnectContinuation?(true)
            self.pendingConnectContinuation = nil
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.awaitingAuthCallback = false
            print("⚠️ Spotify App Remote connection failed: \(error?.localizedDescription ?? "unknown")")
            self.pendingConnectContinuation?(false)
            self.pendingConnectContinuation = nil
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            self.pollTimer?.invalidate()
            self.pollTimer = nil
            self.pendingConnectContinuation?(false)
            self.pendingConnectContinuation = nil
        }
    }
}
