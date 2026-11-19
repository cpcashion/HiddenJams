//
//  OnboardingView.swift
//  HiddenJams
//
//  Onboarding v5 (Chris approved Nov 18, 2026). Five pages before sign-in
//  inside the app's own paged TabView (so the dots are the live app's
//  dots), one Next in the same slot on every page. Page 5 swaps the Next
//  slot for the two connect buttons. After a service connects, ContentView
//  shows TasteProfileFlowView; onboarding is only marked complete on its
//  final "Start digging".
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var appleMusicService: AppleMusicService
    @EnvironmentObject var sourceManager: MusicSourceManager
    @Binding var isPresented: Bool

    #if DEBUG
    @State private var currentPage = OnboardingSnapshotHooks.introPage   // tooling branch only
    #else
    @State private var currentPage = 0
    #endif
    @State private var genrePicks: Set<String> = GenreCatalog.loadSelected() ?? []
    @State private var isConnectingAppleMusic = false
    @State private var connectError: String?

    private let pageCount = 5
    private var isConnectPage: Bool { currentPage == pageCount - 1 }

    var body: some View {
        ZStack {
            Theme.Colors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingStatPage(isActive: currentPage == 0).tag(0)
                    OnboardingKeepDemoPage(isActive: currentPage == 1).tag(1)
                    OnboardingRarityPage(isActive: currentPage == 2).tag(2)
                    OnboardingMoodPage(picks: $genrePicks).tag(3)
                    OnboardingConnectPage(isActive: currentPage == 4).tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                bottomSlot
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: currentPage) {
            connectError = nil
            // Also persisted on every pill toggle; nothing picked → key stays unset.
            GenreCatalog.saveOnboardingPicks(genrePicks)
        }
    }

    // MARK: - Bottom slot (Next, or the connect buttons on page 5)

    @ViewBuilder
    private var bottomSlot: some View {
        if isConnectPage {
            VStack(spacing: 12) {
                ServiceConnectButton(source: .spotify) {
                    connectError = nil
                    GenreCatalog.saveOnboardingPicks(genrePicks)
                    authManager.startAuth()
                }
                ServiceConnectButton(source: .appleMusic, busy: isConnectingAppleMusic) {
                    GenreCatalog.saveOnboardingPicks(genrePicks)
                    connectAppleMusic()
                }
                if let connectError {
                    VStack(spacing: 6) {
                        Text(connectError)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.error)
                            .multilineTextAlignment(.center)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.lime)
                    }
                    .padding(.horizontal, 22)
                }
            }
        } else {
            OnboardingNextButton {
                withAnimation { currentPage = min(currentPage + 1, pageCount - 1) }
            }
        }
    }

    private func connectAppleMusic() {
        isConnectingAppleMusic = true
        connectError = nil
        Task {
            let authorized = await appleMusicService.requestAuthorization()
            await MainActor.run {
                isConnectingAppleMusic = false
                if authorized {
                    // The taste-profile flow reads the library next.
                    sourceManager.refresh()
                } else {
                    connectError = "Apple Music access was not granted. You can enable it in Settings → Privacy → Media & Apple Music."
                }
            }
        }
    }
}

#Preview("Onboarding v5") {
    let auth = SpotifyAuthManager()
    let apple = AppleMusicService()
    return OnboardingView(isPresented: .constant(true))
        .environmentObject(auth)
        .environmentObject(apple)
        .environmentObject(MusicSourceManager(spotifyAuth: auth, appleMusic: apple))
        .preferredColorScheme(.dark)
}
