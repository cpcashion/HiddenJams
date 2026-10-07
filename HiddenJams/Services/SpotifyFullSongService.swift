//
//  SpotifyFullSongService.swift
//  HiddenJams
//
//  In-app full-song playback for Spotify Premium users via the Spotify
//  iOS SDK App Remote. Plays the full track inside Hidden Jams — the user
//  never leaves the app. Requires the Spotify app installed + Premium.
//
//  Auth reuses the app's existing PKCE access token (which now includes
//  the `app-remote-control` scope), so there's no second login flow.
//

import Foundation
import Combine
import SpotifyiOS
import UIKit

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
    private var pendingConnectContinuation: ((Bool) -> Void)?

    /// True when the Spotify app is installed (App Remote requires it).
    var isSpotifyAppInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
    }

    /// Connects the App Remote using the app's Spotify access token.
    /// The token must carry the `app-remote-control` scope.
    func connect(accessToken: String) async -> Bool {
        if appRemote.isConnected { return true }
        guard isSpotifyAppInstalled, !accessToken.isEmpty else { return false }
        appRemote.connectionParameters.accessToken = accessToken
        return await withCheckedContinuation { continuation in
            var resumed = false
            self.pendingConnectContinuation = { success in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: success)
            }
            // Safety timeout — don't hang forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, !resumed else { return }
                resumed = true
                self.pendingConnectContinuation = nil
                continuation.resume(returning: self.appRemote.isConnected)
            }
            self.appRemote.connect()
        }
    }

    func play(uri: String, accessToken: String) async -> Bool {
        guard await connect(accessToken: accessToken) else { return false }
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
            self.pendingConnectContinuation?(true)
            self.pendingConnectContinuation = nil
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
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
