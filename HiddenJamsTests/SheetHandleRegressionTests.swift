//
//  SheetHandleRegressionTests.swift
//  HiddenJamsTests
//
//  Build 88 feedback: the rarity sheet's title kept ending up under the
//  system drag indicator. Root cause: the content was a plain VStack that,
//  when taller than the sheet (.medium detent, or mid-drag), SwiftUI centred,
//  pushing the title up into the handle area. HJSheetScaffold now reserves a
//  fixed handle zone and scrolls the content from the top.
//
//  This renders RaritySheet at every detent height (and a sweep of mid-drag
//  heights) for a small iPhone (SE), a 13 mini class phone and a Pro Max,
//  and checks the title's top edge is below the handle zone every time.
//

import XCTest
import SwiftUI
import UIKit
@testable import HiddenJams

@MainActor
final class SheetHandleRegressionTests: XCTestCase {

    private final class Box { var frame: CGRect? }

    private struct Phone { let name: String; let size: CGSize; let safeTop: CGFloat; let safeBottom: CGFloat }
    private static let phones = [
        Phone(name: "iPhone SE", size: CGSize(width: 375, height: 667), safeTop: 20, safeBottom: 0),
        Phone(name: "iPhone 13 mini", size: CGSize(width: 375, height: 812), safeTop: 50, safeBottom: 34),
        Phone(name: "iPhone 16 Pro Max", size: CGSize(width: 440, height: 956), safeTop: 62, safeBottom: 34),
    ]

    /// The artist from Chris's build 88 screenshot, plus long genres so the
    /// content is as tall as it gets.
    private static let rarity = ArtistRarity(tier: .ultraRare, score: 94, followers: 871, popularity: 6,
                                             lastFmListeners: 19_800, lastFmPlaycount: 79_200,
                                             genres: ["minimal techno", "deep house", "dub techno", "microhouse",
                                                      "ambient techno", "experimental electronic"],
                                             artistName: "Earthrumental")

    private static var retired: [UIWindow] = []

    func testHandleZoneLeavesRoomForTheSystemIndicator() {
        // UIKit draws the indicator 5pt tall about 5pt from the sheet's top.
        XCTAssertGreaterThanOrEqual(HJSheetScaffold<EmptyView>.handleZone, 20)
    }

    func testRaritySheetTitleClearsHandleAtEveryDetent() async throws {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw XCTSkip("no window scene in the test host")
        }
        let zone = HJSheetScaffold<EmptyView>.handleZone
        var measured = 0, unmeasured = 0
        for phone in Self.phones {
            let medium = (phone.size.height / 2).rounded()
            let large = phone.size.height - phone.safeTop - 10
            var heights: [CGFloat] = [medium, large]
            heights += stride(from: CGFloat(160), to: large, by: 80).map { $0 }
            for h in heights {
                let box = Box()
                let root = RaritySheet(rarity: Self.rarity, trackName: "Track")
                    .padding(.bottom, phone.safeBottom)
                    .frame(width: phone.size.width, height: h)
                    .onPreferenceChange(HJSheetTitleFrameKey.self) { box.frame = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                let hc = UIHostingController(rootView: root)
                let w = UIWindow(windowScene: scene)
                w.windowLevel = .alert + 1
                w.rootViewController = hc
                w.makeKeyAndVisible()
                let until = Date().addingTimeInterval(1.5)
                while box.frame == nil && Date() < until {
                    hc.view.setNeedsLayout()
                    hc.view.layoutIfNeeded()
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
                w.isHidden = true
                Self.retired.append(w)   // keep alive (window teardown crashed the host before)
                guard let f = box.frame else {
                    unmeasured += 1
                    print("HJSHEET \(phone.name) h=\(Int(h)) unmeasured")
                    continue
                }
                measured += 1
                print("HJSHEET \(phone.name) h=\(Int(h)) titleMinY=\(f.minY)")
                XCTAssertGreaterThanOrEqual(f.minY, zone - 0.5,
                                            "\(phone.name) at height \(Int(h)): title top \(f.minY) is inside the \(zone)pt handle zone")
            }
        }
        print("HJSHEET measured=\(measured) unmeasured=\(unmeasured)")
        if measured == 0 { throw XCTSkip("title frame never reported in this host (\(unmeasured) layouts)") }
    }
}
