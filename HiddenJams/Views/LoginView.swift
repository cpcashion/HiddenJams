//
//  LoginView.swift
//  SpotifyHiddenGems
//
//  Beautiful authentication screen with Spotify branding
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @State private var isAnimating = false
    
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
                    FeatureRow(icon: "globe", text: "Discover gems from across Spotify")
                    FeatureRow(icon: "star.fill", text: "Songs with <1,000 streams")
                }
                .padding(.horizontal, Theme.Spacing.xl)
                
                Spacer()
                
                // Connect button
                Button(action: {
                    withAnimation(.spring()) {
                        authManager.startAuth()
                    }
                }) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                        
                        Text("Connect with Spotify")
                            .font(Theme.Typography.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.primaryGradient)
                    .cornerRadius(Theme.CornerRadius.lg)
                    .applyShadow(Theme.Shadows.medium)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
                
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
