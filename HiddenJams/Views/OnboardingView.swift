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

    @State private var isConnectingAppleMusic = false
    @State private var connectError: String?

    var body: some View {
        OnboardingPager(
            startPage: 0,
            initialPicks: TasteCopy.orderedPicks(GenreCatalog.loadSelected() ?? []),
            connectingApple: isConnectingAppleMusic,
            connectError: $connectError,
            onSpotify: { picks in
                connectError = nil
                GenreCatalog.saveOnboardingPicks(Set(picks))
                authManager.startAuth()
            },
            onApple: { picks in
                GenreCatalog.saveOnboardingPicks(Set(picks))
                connectAppleMusic()
            },
            persist: { picks in GenreCatalog.saveOnboardingPicks(Set(picks)) }
        )
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

/// The five screens, glow, dots and dock (no service objects needed, so the
/// DEBUG parity captures render exactly this).
struct OnboardingPager: View {
    let connectingApple: Bool
    @Binding var connectError: String?
    let onSpotify: ([String]) -> Void
    let onApple: ([String]) -> Void
    let persist: ([String]) -> Void

    @State private var page: Int
    @State private var direction: CGFloat = 1
    /// Picks, lowercased (the `selectedGenres` set, kept sorted).
    @State private var picks: [String]
    @State private var pulse = 0
    /// Card drags (screen 2) own their gesture; the page swipe yields to them.
    @State private var cardLock = OBCardDragLock()

    private let pageCount = 5
    private var isConnectPage: Bool { page == pageCount - 1 }

    init(startPage: Int, initialPicks: [String], connectingApple: Bool, connectError: Binding<String?>,
         onSpotify: @escaping ([String]) -> Void, onApple: @escaping ([String]) -> Void,
         persist: @escaping ([String]) -> Void) {
        _page = State(initialValue: startPage)
        _picks = State(initialValue: initialPicks)
        self.connectingApple = connectingApple
        _connectError = connectError
        self.onSpotify = onSpotify
        self.onApple = onApple
        self.persist = persist
    }

    private var pickSet: Binding<Set<String>> {
        Binding(get: { Set(picks) }, set: { picks = $0.map { $0.lowercased() }.sorted() })
    }

    var body: some View {
        OBMetricsReader {
            ZStack {
                OBGlowBackground(screen: page, pulseToken: pulse)

                ZStack {
                    screen(page)
                        .id(page)
                        .transition(.obPage(direction))
                }
                .environment(\.obCardDragLock, cardLock)
                .contentShape(Rectangle())
                .simultaneousGesture(swipe)

                OBDock(dots: (count: pageCount, index: page), two: isConnectPage) {
                    if isConnectPage {
                        OBBrandButton(brand: .spotify) { onSpotify(picks) }
                        OBBrandButton(brand: .appleMusic, busy: connectingApple) { onApple(picks) }
                    } else {
                        OBNextButton { go(page + 1) }
                    }
                }
                errorBanner
            }
        }
        .onChange(of: page) {
            connectError = nil
            // Also persisted on every pill toggle; nothing picked → key stays unset.
            persist(picks)
        }
        .onChange(of: picks) { persist(picks) }
    }

    @ViewBuilder
    private func screen(_ i: Int) -> some View {
        switch i {
        case 0: OBIntroScreen()
        case 1: OBKeepScreen()
        case 2: OBRarityDemoScreen()
        case 3: OBMoodScreen(picks: pickSet, onTap: { pulse += 1 })
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
    /// moves one screen; never required, Next always works. A drag that
    /// started on a swipeable card (screen 2) belongs to the card only, so
    /// it never pages (build 93: swiping a card right used to jump back to
    /// screen 1).
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { v in
                guard !cardLock.isHeld() else { return }
                if let target = OBPagerSwipe.target(page: page, pageCount: pageCount,
                                                    dx: v.translation.width, dy: v.translation.height) {
                    go(target)
                }
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
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 200)
        }
    }
}

/// Pure page-swipe rule (unit-tested).
enum OBPagerSwipe {
    static func target(page: Int, pageCount: Int, dx: CGFloat, dy: CGFloat) -> Int? {
        guard abs(dx) >= 70, abs(dy) <= 50 else { return nil }
        if dx < 0 && page < pageCount - 1 { return page + 1 }
        if dx > 0 && page >= 1 { return page - 1 }
        return nil
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
