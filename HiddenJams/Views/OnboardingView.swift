//
//  OnboardingView.swift
//  HiddenJams
//
//  Onboarding v5, built to the approved prototype
//  (https://cpcashion.github.io/hiddenjams-onboarding-v4/v5/). Five screens
//  before sign-in over the animated glow, with the prototype's page dots
//  and one flat lime Next in the same slot on every screen; screen 5 swaps
//  it for the two connect buttons. After a service connects, ContentView
//  shows TasteProfileFlowView; onboarding is only marked complete on its
//  final "Start digging".
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    @EnvironmentObject var appleMusicService: AppleMusicService
    @EnvironmentObject var sourceManager: MusicSourceManager
    @Binding var isPresented: Bool

    @State private var page: Int
    @State private var direction: CGFloat = 1
    @State private var genrePicks: Set<String>
    @State private var isConnectingAppleMusic = false
    @State private var connectError: String?
    @State private var pulse = 0

    private let pageCount = 5
    private var isConnectPage: Bool { page == pageCount - 1 }

    init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
        _page = State(initialValue: 0)
        _genrePicks = State(initialValue: GenreCatalog.loadSelected() ?? [])
    }

    #if DEBUG
    /// Parity captures only: open on a given screen with given picks
    /// (nothing is written to UserDefaults until a pill is tapped).
    init(debugStartPage: Int, picks: Set<String>) {
        _isPresented = .constant(true)
        _page = State(initialValue: debugStartPage)
        _genrePicks = State(initialValue: picks)
    }
    #endif

    var body: some View {
        OBMetricsReader {
            ZStack {
                OBGlowBackground(screen: page, pulseToken: pulse)

                ZStack {
                    screen(page)
                        .id(page)
                        .transition(.obPage(direction))
                }
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)

                OBDock(dots: (count: pageCount, index: page), two: isConnectPage) {
                    if isConnectPage {
                        OBBrandButton(brand: .spotify) {
                            connectError = nil
                            GenreCatalog.saveOnboardingPicks(genrePicks)
                            authManager.startAuth()
                        }
                        OBBrandButton(brand: .appleMusic, busy: isConnectingAppleMusic) {
                            GenreCatalog.saveOnboardingPicks(genrePicks)
                            connectAppleMusic()
                        }
                    } else {
                        OBNextButton { go(page + 1) }
                    }
                }
                .overlay(alignment: .bottom) { errorBanner }
            }
        }
        .ignoresSafeArea(.keyboard)
        .preferredColorScheme(.dark)
        .onChange(of: page) {
            connectError = nil
            // Also persisted on every pill toggle; nothing picked → key stays unset.
            GenreCatalog.saveOnboardingPicks(genrePicks)
        }
        .onChange(of: genrePicks) { _, picks in GenreCatalog.saveOnboardingPicks(picks) }
    }

    @ViewBuilder
    private func screen(_ i: Int) -> some View {
        switch i {
        case 0: OBIntroScreen()
        case 1: OBKeepScreen()
        case 2: OBRarityDemoScreen()
        case 3: OBMoodScreen(picks: $genrePicks, onTap: { pulse += 1 })
        default: OBConnectScreen()
        }
    }

    private func go(_ n: Int) {
        let target = max(0, min(pageCount - 1, n))
        guard target != page else { return }
        direction = target > page ? 1 : -1
        withAnimation(OB.pageSpring) { page = target }
    }

    /// Like the prototype: a horizontal swipe of ≥70pt (and ≤50pt vertical)
    /// moves one screen; never required, Next always works.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) >= 70, abs(dy) <= 50 else { return }
                if dx < 0 && page <= 3 { go(page + 1) } else if dx > 0 && page >= 1 { go(page - 1) }
            }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let connectError, isConnectPage {
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
                .foregroundStyle(OB.lime)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(OB.surface.opacity(0.95)))
            .padding(.horizontal, 22)
            .padding(.bottom, 200)
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
}
