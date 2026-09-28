import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var appleMusicService: AppleMusicService
    @EnvironmentObject var sourceManager: MusicSourceManager
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var isConnectingAppleMusic = false
    @State private var appleMusicError: String?

    let items: [OnboardingItem] = [
        OnboardingItem(
            title: "Uncover Hidden Gems",
            description: "Dig deep for unheard tracks or stay mainstream. You control the crowd to find your perfect sound.",
            systemImage: "sparkles"
        ),
        OnboardingItem(
            title: "Swipe to Playlist",
            description: "Swipe right to save. We automatically build a \"Hidden Gems\" playlist in your Spotify library with every like.",
            systemImage: "hand.draw.fill"
        ),
        OnboardingItem(
            title: "Connect Your Music",
            description: "Link Spotify, Apple Music, or both to start discovering and saving music instantly.",
            systemImage: "music.note" // "Spotify-like" generic
        )
    ]

    var body: some View {
        ZStack {
            // Background
            Theme.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack {
                Spacer()

                TabView(selection: $currentPage) {
                    ForEach(0..<items.count, id: \.self) { index in
                        OnboardingPage(item: items[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 520)
                .padding(.bottom, 40) // Move dots lower

                Spacer()

                if currentPage < items.count - 1 {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        Text("Next")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.buttonText) // Dark grey text
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AnyShapeStyle(Theme.Colors.gemGold))
                            .cornerRadius(12)
                            .shadow(color: Theme.Colors.gemGold.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                } else {
                    // Final page: connect Spotify and/or Apple Music
                    VStack(spacing: 12) {
                        Button(action: {
                            authManager.startAuth()
                        }) {
                            HStack {
                                Image(systemName: "music.note.list")
                                Text(sourceManager.spotifyConnected ? "Spotify Connected ✓" : "Connect with Spotify")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AnyShapeStyle(Theme.Colors.primaryGradient))
                            .cornerRadius(12)
                            .shadow(color: Theme.Colors.spotifyGreen.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(sourceManager.spotifyConnected)

                        Button(action: { connectAppleMusic() }) {
                            HStack {
                                Image(systemName: "apple.logo")
                                Text(sourceManager.appleMusicConnected ? "Apple Music Connected ✓" : "Connect with Apple Music")
                                    .font(.headline)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color(hex: "FA243C"), Color(hex: "FC5C72")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ))
                            .cornerRadius(12)
                            .shadow(color: Color(hex: "FA243C").opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .disabled(sourceManager.appleMusicConnected)

                        if let error = appleMusicError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 50)
                }
            }
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
        }
    }

    private func completeOnboarding() {
        withAnimation {
            isPresented = false
        }
    }
}
