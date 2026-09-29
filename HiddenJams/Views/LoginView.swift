//
//  LoginView.swift
//  SpotifyHiddenGems
//
//  Beautiful authentication screen — connect Spotify, Apple Music, or both
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var appleMusicService: AppleMusicService
    @EnvironmentObject var sourceManager: MusicSourceManager
    @EnvironmentObject var profileAnalyzer: AIProfileAnalyzer
    @State private var isAnimating = false
    @State private var isConnectingAppleMusic = false
    @State private var appleMusicError: String?

    var body: some View {
        ZStack {
            // Animated background
            AnimatedGradientBackground()

            VStack(spacing: 0) {
                Spacer() // Push everything down

                // App branding
                VStack(spacing: Theme.Spacing.md) {
                    // Icon - App Icon with rounded corners
                    Image("AppIconImage")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 28))

                    // Title
                    Text("Hidden Jams")
                        .font(Theme.Typography.largeTitle)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.top, 5)

                    // Paragraph - separated with more padding
                    Text("Discover Underground Music Tailored to your Unique Taste Profile")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Theme.Spacing.xxl)
                }
                .padding(.bottom, 40) // More space before bullets

                // Features
                VStack(spacing: Theme.Spacing.md) {
                    FeatureRow(icon: "music.note", text: "AI analyzes your liked songs")
                    FeatureRow(icon: "globe", text: "Discover gems from across the underground")
                    FeatureRow(icon: "star.fill", text: "Songs with <1,000 streams")
                }
                .padding(.horizontal, Theme.Spacing.xl)

                Spacer()

                // Connect buttons
                VStack(spacing: Theme.Spacing.md) {
                    // Spotify button
                    connectButton(
                        title: sourceManager.spotifyConnected ? "Spotify Connected ✓" : "Connect with Spotify",
                        icon: "music.note.list",
                        gradient: Theme.Colors.primaryGradient,
                        disabled: sourceManager.spotifyConnected,
                        action: {
                            withAnimation(.spring()) {
                                authManager.startAuth()
                            }
                        }
                    )

                    // Apple Music button
                    connectButton(
                        title: sourceManager.appleMusicConnected ? "Apple Music Connected ✓" : "Connect with Apple Music",
                        icon: "apple.logo",
                        gradient: LinearGradient(
                            colors: [Color(hex: "FA243C"), Color(hex: "FC5C72")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        disabled: sourceManager.appleMusicConnected,
                        action: { connectAppleMusic() }
                    )

                    if sourceManager.hasConnectedSource {
                        Text("You can connect the other service too — we'll blend both libraries.")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }

                    if let error = appleMusicError {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.md)

                // Privacy notice
                Text("We'll never post or modify your music without permission")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .onAppear {
            isAnimating = true
        }
        .overlay {
            if isConnectingAppleMusic {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView("Connecting to Apple Music…")
                        .tint(.white)
                        .foregroundColor(.white)
                }
            }
        }
    }

    // MARK: - Connect Button

    private func connectButton(
        title: String,
        icon: String,
        gradient: LinearGradient,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.title2)

                Text(title)
                    .font(Theme.Typography.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(disabled ? AnyShapeStyle(Color.gray.opacity(0.4)) : AnyShapeStyle(gradient))
            .cornerRadius(Theme.CornerRadius.lg)
            .applyShadow(Theme.Shadows.medium)
        }
        .disabled(disabled)
    }

    // MARK: - Apple Music

    private func connectAppleMusic() {
        isConnectingAppleMusic = true
        appleMusicError = nil
        Task {
            let authorized = await appleMusicService.requestAuthorization()
            await MainActor.run {
                isConnectingAppleMusic = false
                if authorized {
                    sourceManager.refresh()
                } else {
                    appleMusicError = "Apple Music access was not granted. You can enable it in Settings → Privacy → Media & Apple Music."
                }
            }
            if authorized {
                // Read the library right away — otherwise the dashboard shows
                // a stale profile with no Apple tracks and discovery fails.
                await profileAnalyzer.analyzeAllConnectedSources(spotifyToken: authManager.accessToken)
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Theme.Colors.spotifyGreen)
                .frame(width: 30)

            Text(text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)

            Spacer()
        }
    }
}

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: "0A0E1A"),
                Color(hex: "191414"),
                Color(hex: "1DB954").opacity(0.1)
            ],
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}
