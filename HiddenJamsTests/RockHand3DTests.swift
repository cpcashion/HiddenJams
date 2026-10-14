//
//  RockHand3DTests.swift
//  HiddenJamsTests
//
//  Build 55 replaced the paywall's spinning PNG with a live 3D model. If the
//  USDZ ever drops out of the bundle (renamed, or moved out of the synced
//  HiddenJams/ folder), the paywall quietly falls back to the old flat
//  artwork — these tests turn that into a CI failure instead.
//

import Testing
import Foundation
import SceneKit
import UIKit
@testable import HiddenJams

@MainActor
struct RockHand3DTests {

    @Test("RockHand.usdz ships in the app bundle")
    func modelIsBundled() {
        let url = Bundle.main.url(forResource: RockHandScene.modelName, withExtension: "usdz")
        #expect(url != nil)
    }

    @Test("The model loads with both the hand and the nails")
    func modelLoadsWithBothParts() throws {
        let scene = try #require(RockHandScene.make())

        var colors: [UIColor] = []
        scene.rootNode.enumerateHierarchy { node, _ in
            if let color = node.geometry?.firstMaterial?.diffuse.contents as? UIColor {
                colors.append(color)
            }
        }
        #expect(colors.contains(RockHandScene.skinColor))
        #expect(colors.contains(RockHandScene.nailColor))
    }

    @Test("The model is normalised to unit height, which the camera framing assumes")
    func modelIsUnitHeight() throws {
        let scene = try #require(RockHandScene.make())
        let spinner = try #require(
            scene.rootNode.childNode(withName: RockHandScene.spinnerNodeName, recursively: true)
        )
        let (minBound, maxBound) = spinner.boundingBox
        #expect(abs((maxBound.y - minBound.y) - 1) < 0.01)
    }

    @Test("Reduce Motion stops the spin, and turning it back off restarts it")
    func spinRespectsReduceMotion() throws {
        let scene = try #require(RockHandScene.make())
        let spinner = try #require(
            scene.rootNode.childNode(withName: RockHandScene.spinnerNodeName, recursively: true)
        )

        RockHandScene.setSpinning(true, in: scene)
        #expect(spinner.action(forKey: RockHandScene.spinActionKey) != nil)

        RockHandScene.setSpinning(false, in: scene)
        #expect(spinner.action(forKey: RockHandScene.spinActionKey) == nil)

        RockHandScene.setSpinning(true, in: scene)
        #expect(spinner.action(forKey: RockHandScene.spinActionKey) != nil)
    }
}
