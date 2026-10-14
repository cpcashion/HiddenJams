//
//  RockHand3DView.swift
//  HiddenJams
//
//  The paywall's 🤘 charm, rendered live as a real 3D model (build 55).
//

import SwiftUI
import SceneKit
import UIKit

/// The paywall's rock-hand charm as an actual 3D model.
///
/// Builds 52–54 spun a flat PNG with `rotation3DEffect`. That can only ever
/// turn a *picture* of a hand: edge-on it collapses to a sliver, and halfway
/// round it shows the same picture mirrored. This renders a real mesh
/// (`Resources/RockHand.usdz`) under physically based lighting, so as it turns
/// you see the side of the hand, the thumb pressing the folded fingers down,
/// and the knuckles and fingernails on the back.
///
/// SceneKit rather than RealityKit: SceneKit is soft-deprecated as of iOS 26
/// but remains supported, and gives a transparent background and a plain
/// non-AR camera with no extra setup. `RealityView` on iOS defaults to the AR
/// camera, which on a paywall would risk a camera-permission prompt.
struct RockHand3DView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RockHandSceneView(spinning: !reduceMotion)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rock-on hand")
            .accessibilityAddTraits(.isImage)
    }
}

// MARK: - SceneKit host

private struct RockHandSceneView: UIViewRepresentable {
    let spinning: Bool

    func makeUIView(context: Context) -> UIView {
        guard let scene = RockHandScene.make() else {
            // Model missing or unreadable: show the previous artwork rather
            // than leave a hole at the top of the paywall.
            let fallback = UIImageView(image: UIImage(named: "RockHand"))
            fallback.contentMode = .scaleAspectFit
            return fallback
        }

        let view = SCNView(frame: .zero, options: nil)
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = false
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.loops = true

        RockHandScene.setSpinning(spinning, in: scene)
        view.rendersContinuously = spinning
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? SCNView, let scene = view.scene else { return }
        RockHandScene.setSpinning(spinning, in: scene)
        view.rendersContinuously = spinning
    }
}

// MARK: - Scene

/// Loads the bundled model and stages it with a camera, lights and materials.
/// Internal (not private) so tests can verify the bundled model loads.
enum RockHandScene {
    static let modelName = "RockHand"
    static let spinnerNodeName = "RockHandSpinner"
    static let spinActionKey = "spin"

    /// One full turn every 8 seconds — close to the old 9s coin-spin.
    static let secondsPerTurn: TimeInterval = 8

    /// Brand amber (Theme.Colors.gemGold family). Fixed in both appearance
    /// modes, like the artwork it replaces, so the charm stays orange on the
    /// light theme instead of turning accent-blue.
    static let skinColor = UIColor(red: 0xF2 / 255, green: 0x86 / 255, blue: 0x0C / 255, alpha: 1)
    static let nailColor = UIColor(red: 0xF9 / 255, green: 0xBE / 255, blue: 0x78 / 255, alpha: 1)

    /// Returns nil if the model is missing or fails to parse, so callers can
    /// fall back to static artwork.
    static func make(bundle: Bundle = .main) -> SCNScene? {
        guard let url = bundle.url(forResource: modelName, withExtension: "usdz"),
              let loaded = try? SCNScene(url: url, options: nil)
        else { return nil }

        let model = SCNNode()
        for child in loaded.rootNode.childNodes {
            model.addChildNode(child)
        }
        guard applyMaterials(to: model) > 0 else { return nil }

        // Normalise to a height of 1 and centre vertically. Horizontally the
        // model's origin already sits on the palm's axis, which is the axis it
        // should spin around — the bounding-box centre is pulled sideways by
        // the thumb and would make the hand wobble as it turns.
        let (minBound, maxBound) = model.boundingBox
        let height = maxBound.y - minBound.y
        guard height > 0 else { return nil }
        let scale = 1 / height
        model.scale = SCNVector3(scale, scale, scale)
        model.position = SCNVector3(0, -(minBound.y + maxBound.y) / 2 * scale, 0)

        let spinner = SCNNode()
        spinner.name = spinnerNodeName
        spinner.addChildNode(model)

        // A slight forward tilt shows a little of the top of the hand, which
        // reads as 3D far better than a dead-level profile.
        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(0.08, 0, 0)
        tilt.addChildNode(spinner)

        let scene = SCNScene()
        scene.rootNode.addChildNode(tilt)
        scene.rootNode.addChildNode(cameraNode())
        scene.rootNode.addChildNode(directionalLight(intensity: 700, from: SCNVector3(-1.5, 2.2, 2.5)))
        // Rim light from behind so the silhouette separates from a black background.
        scene.rootNode.addChildNode(directionalLight(intensity: 450, from: SCNVector3(1.8, 1.2, -2.2)))
        scene.lightingEnvironment.contents = studioEnvironment()
        scene.lightingEnvironment.intensity = 1.5
        return scene
    }

    /// Starts or stops the spin. When stopped (Reduce Motion), the hand rests
    /// at a three-quarter turn, which still shows that it's 3D.
    static func setSpinning(_ spinning: Bool, in scene: SCNScene) {
        guard let spinner = scene.rootNode.childNode(withName: spinnerNodeName, recursively: true) else { return }
        let isSpinning = spinner.action(forKey: spinActionKey) != nil

        if spinning, !isSpinning {
            let turn = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: secondsPerTurn)
            spinner.runAction(.repeatForever(turn), forKey: spinActionKey)
        } else if !spinning {
            spinner.removeAction(forKey: spinActionKey)
            spinner.eulerAngles = SCNVector3(0, -0.45, 0)
        }
    }

    /// Assigns the charm's materials by part. Returns how many meshes it found.
    @discardableResult
    static func applyMaterials(to model: SCNNode) -> Int {
        let skin = glossyMaterial(color: skinColor, roughness: 0.34, clearCoat: 1.0)
        let nail = glossyMaterial(color: nailColor, roughness: 0.22, clearCoat: 0.6)

        var meshes = 0
        model.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            meshes += 1
            // The USD export names the parts "Hand" and "Nails"; the mesh may
            // sit on the named node or on a child of it.
            let isNail = sequence(first: node, next: { $0.parent })
                .contains { ($0.name ?? "").localizedCaseInsensitiveContains("nail") }
            geometry.materials = [isNail ? nail : skin]
        }
        return meshes
    }

    // MARK: Staging

    private static func glossyMaterial(color: UIColor, roughness: CGFloat, clearCoat: CGFloat) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.roughness.contents = roughness
        material.metalness.contents = 0.0
        // A clear coat over a softer base gives the candy-glaze look of the
        // previous artwork, with highlights that slide over the curves as it turns.
        material.clearCoat.contents = clearCoat
        material.clearCoatRoughness.contents = 0.05
        return material
    }

    private static func cameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.1
        camera.zFar = 20

        let node = SCNNode()
        node.camera = camera
        // With a 30° field of view the unit-height model fills ~70% of the
        // frame, leaving room for the thumb as it swings toward the camera.
        node.position = SCNVector3(0, 0, 2.7)
        return node
    }

    private static func directionalLight(intensity: CGFloat, from position: SCNVector3) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.intensity = intensity
        light.color = UIColor.white

        let node = SCNNode()
        node.light = light
        node.position = position
        node.look(at: SCNVector3(0, 0, 0))
        return node
    }

    /// A simple equirectangular studio: bright overhead, dark floor, and
    /// softbox panels whose reflections give the clear coat its highlights.
    /// Three panels spaced around the horizon mean there is always a highlight
    /// sweeping across the hand, whichever way it faces. Generated in code so
    /// there is no image asset or licence to track.
    private static func studioEnvironment() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let colors = [
                UIColor(white: 0.92, alpha: 1).cgColor, // zenith
                UIColor(white: 0.50, alpha: 1).cgColor, // horizon
                UIColor(white: 0.08, alpha: 1).cgColor, // floor
            ] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }

            cg.setFillColor(UIColor.white.cgColor)
            let spacing = size.width / 3
            for index in 0..<3 {
                let panel = CGRect(x: 40 + CGFloat(index) * spacing, y: 48, width: 92, height: 62)
                cg.addPath(UIBezierPath(roundedRect: panel, cornerRadius: 18).cgPath)
                cg.fillPath()
            }
        }
    }
}
