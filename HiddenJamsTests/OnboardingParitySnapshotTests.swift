//
//  OnboardingParitySnapshotTests.swift
//  HiddenJamsTests
//
//  Parity captures for onboarding v5 (design tooling, DEBUG builds only).
//  Renders each screen in its own window on the CI simulator (iPhone 16 Pro,
//  402x874 pt, real safe areas) and prints each frame as base64 lines in the
//  test log; decode with design-research/onboarding-v5/parity/decode.py.
//
//  Runs only while `HiddenJamsTests/ParityCapture.enabled` exists in the
//  checkout (delete that file to turn the captures off).
//

import XCTest
import SwiftUI
import UIKit
@testable import HiddenJams

@MainActor
final class OnboardingParitySnapshotTests: XCTestCase {

    private var window: UIWindow?

    private static var enabled: Bool {
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ParityCapture.enabled")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    /// Survives a crash + relaunch: a state that crashed is skipped next time.
    private static var progressDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".hjsnap-progress")
    }
    private func attempt(_ name: String) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.progressDir, withIntermediateDirectories: true)
        let f = Self.progressDir.appendingPathComponent(name)
        if fm.fileExists(atPath: f.path) { step("CRASHED-BEFORE \(name) (skipping)"); return false }
        fm.createFile(atPath: f.path, contents: Data())
        return true
    }
    private func done(_ name: String) { try? FileManager.default.removeItem(at: Self.progressDir.appendingPathComponent(name)) }

    /// Prints the newest HiddenJams crash report's crashed-thread frames.
    private func dumpCrashReports() {
        let dirs = ["/Users/runner/Library/Logs/DiagnosticReports", NSHomeDirectory() + "/Library/Logs/DiagnosticReports"]
        for d in dirs {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: d) else { step("no dir \(d)"); continue }
            for f in files.sorted() where f.hasPrefix("HiddenJams") {
                guard let text = try? String(contentsOfFile: d + "/" + f, encoding: .utf8) else { continue }
                step("CRASHREPORT \(f) \(text.count)")
                for line in text.split(separator: "\n").prefix(400) { print("HJCRASH \(line.prefix(600))") }
            }
        }
        fflush(stdout)
    }

    private func step(_ s: String) { print("HJSNAP-STEP \(s)"); fflush(stdout) }

    private static var retired: [UIWindow] = []

    private func show(_ name: String) async {
        step("show \(name)")
        // The onboarding screens only read the auth/source managers inside
        // button actions, which the captures never tap.
        let root: AnyView = name == "paywall"
            ? AnyView(PaywallView().environmentObject(SubscriptionManager.shared))
            : AnyView(OnboardingParityFixtures.screen(name))
        let hc = UIHostingController(rootView: root)
        hc.overrideUserInterfaceStyle = .dark
        hc.view.backgroundColor = UIColor(red: 11 / 255, green: 11 / 255, blue: 15 / 255, alpha: 1)
        // A fresh window per state: reusing one window by swapping its root
        // left some screens frozen at their first frame.
        // Old windows are hidden but kept alive: tearing them down hit a
        // host malloc crash (freed static 0x262543f40) on the next swap.
        if let old = window {
            old.isHidden = true
            Self.retired.append(old)
            window = nil
            await spin(until: Date().addingTimeInterval(0.15))
        }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.overrideUserInterfaceStyle = .dark
        window = w
        step("window ready")
        OnboardingParityFixtures.epoch = Date()
        OnboardingParityFixtures.settleGlow = true
        window?.rootViewController = hc
        window?.makeKeyAndVisible()
        step("visible scene=\(scene.activationState.rawValue) app=\(UIApplication.shared.applicationState.rawValue)")
    }

    private func spin(until t: Date) async {
        // On the CI simulator the host scene isn't foreground-active, so
        // display links (SwiftUI animations, TimelineView) barely tick.
        // A layout pass makes the hosting view render at the current time.
        var iters = 0, worst = 0.0
        let began = Date()
        while Date() < t {
            let it = Date()
            iters += 1
            defer { worst = max(worst, Date().timeIntervalSince(it)) }
            if let v = window?.rootViewController?.view {
                v.setNeedsLayout()
                v.layoutIfNeeded()
            }
            // A presented sheet lives in its own controller's view.
            if let pv = window?.rootViewController?.presentedViewController?.view {
                pv.setNeedsLayout()
                pv.layoutIfNeeded()
            }
            // Yield the main actor instead of spinning the run loop inside
            // a main-actor job: nested spinning ran the screens' .task jobs
            // re-entrantly and crashed the host (malloc 0x262543f40).
            let left = max(0, min(t.timeIntervalSince(Date()), 1.0 / 60))
            try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
        }
        print(String(format: "HJSNAP-PERF spin %.2fs iters=%d worst=%.0fms", Date().timeIntervalSince(began), iters, worst * 1000))
    }

    /// Frames are rendered at their offsets but written out after the
    /// state is done, so slow logging never delays the next frame.
    private var pending: [(file: String, image: UIImage, settled: Bool, size: CGSize)] = []

    private func emit(_ file: String, settled: Bool) {
        guard let w = window else { return }
        let e0 = Date()
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = settled ? 3 : 1.5
        fmt.opaque = true
        fmt.preferredRange = .standard // sRGB, like the prototype captures (not P3)
        let img = UIGraphicsImageRenderer(bounds: w.bounds, format: fmt).image { _ in
            _ = w.drawHierarchy(in: w.bounds, afterScreenUpdates: true)
        }
        pending.append((file, img, settled, w.bounds.size))
        print(String(format: "HJSNAP-PERF draw %@ %.0fms", file, Date().timeIntervalSince(e0) * 1000))
    }

    /// Screens-93 tooling: PNGs per simulator under <repo>/screens-out/<device>/.
    private static var pngDir: URL {
        let dev = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name)
            .replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("screens-out").appendingPathComponent(dev)
    }

    private func flush() {
        for p in pending where p.settled {
            try? FileManager.default.createDirectory(at: Self.pngDir, withIntermediateDirectories: true)
            let name = (p.file as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: "_") + ".png"
            if let png = p.image.pngData() {
                try? png.write(to: Self.pngDir.appendingPathComponent(name))
                print("HJSNAP-PNG \(Self.pngDir.lastPathComponent)/\(name) \(png.count)")
            }
        }
        pending.removeAll()
        return
        for p in pending {
            guard let data = p.image.jpegData(compressionQuality: p.settled ? 0.92 : 0.8) else {
                print("HJSNAP-FAIL \(p.file)"); continue
            }
            let b64 = data.base64EncodedString()
            var lines = ["HJSNAP-BEGIN \(p.file) \(data.count) \(Int(p.size.width))x\(Int(p.size.height))"]
            var i = 0, idx = b64.startIndex
            while idx < b64.endIndex {
                let end = b64.index(idx, offsetBy: 6000, limitedBy: b64.endIndex) ?? b64.endIndex
                lines.append("HJSNAP|\(p.file)|\(i)|\(b64[idx..<end])")
                idx = end; i += 1
            }
            lines.append("HJSNAP-END \(p.file) \(i)")
            print(lines.joined(separator: "\n"))
            fflush(stdout)
        }
        pending.removeAll()
    }

    /// One capture: a fixture name, motion offsets (s) and the settle time
    /// (same names, offsets and settle times as shoot_proto_device.py).
    private struct Shot {
        let name: String; var motion: [Double] = []; let settled: Double; var file: String? = nil
        /// Also emit FILE_bottom.jpg after scrolling the main list to the end.
        var scrollBottom = false
    }

    private static var shots: [Shot] {
        var list: [Shot] = [
            Shot(name: "profile-after", settled: 4.0, file: "07-profile.jpg"),
            Shot(name: "paywall", settled: 3.0, file: "06-paywall.jpg"),
            Shot(name: "profile-unlimited-paywall", settled: 5.0, file: "08-profile-paywall.jpg"),
        ]
        let screens: [Shot] = [
            Shot(name: "01-intro", motion: [0.4, 0.8, 1.2, 1.6, 2.0, 2.6, 3.4], settled: 6.0),
            Shot(name: "03-rarity", motion: [0.3, 0.6, 0.9, 1.2, 1.6, 2.0, 2.6, 3.4], settled: 5.0),
            Shot(name: "04a-mood-none", motion: [0.3], settled: 2.0),
            Shot(name: "04-mood", settled: 2.0),
            Shot(name: "05-connect", motion: [0.4, 1.2, 2.0], settled: 3.5),
            Shot(name: "07-genres", motion: [0.2, 0.5, 0.8], settled: 3.0),
            Shot(name: "08-rarity", motion: [0.2, 0.5, 0.9, 1.4], settled: 3.0),
            Shot(name: "09-artists", motion: [0.3, 0.6], settled: 3.0),
            Shot(name: "09-artists-apple", settled: 3.0),
            Shot(name: "10-deepest", motion: [0.3, 0.6], settled: 3.0),
            Shot(name: "10-deepest-spotify", settled: 3.0),
            Shot(name: "10-deepest-nopicks", settled: 3.0),
            Shot(name: "11-fresh", motion: [0.3], settled: 3.0),
            Shot(name: "11-fresh-nopicks", settled: 3.0),
        ]
        // Loading: the state frozen at each prototype offset (no clock task),
        // written as static/NAME[_tSS.SS].jpg. Then the live clock versions.
        let loading: [(String, [Double], Double)] = [("06-loading", [0.3, 0.8, 1.5, 2.5, 3.4, 4.2, 5.2, 6.5, 7.8], 8.7),
                                                     ("06-loading-apple", [4.2], 8.7),
                                                     ("06-loading-empty", [1.0, 2.2], 4.1)]
        for (n, motion, settled) in loading {
            list.append(Shot(name: "static:\(n):\(Int(settled * 1000))", settled: 3.0, file: "static/\(n).jpg"))
            for t in motion {
                list.append(Shot(name: "static:\(n):\(Int(t * 1000))", settled: 3.0,
                                 file: "static/\(n)_t\(String(format: "%05.2f", t)).jpg"))
            }
        }
        // 02: the keep script frozen at the prototype's 8.6 s frame (no wall clock).
        list.append(Shot(name: "static-keep", settled: 3.0, file: "02-keep.jpg"))
        list += screens
        // Build 88 fixes (build88-fixes/): rarity sheet at both detents on a
        // small and a large iPhone, pre-fix vs fixed; facts card; Profile.
        for v in ["old", "new"] {
            for d in ["se", "promax"] {
                for det in ["medium", "large"] {
                    list.append(Shot(name: "sheet:\(v):\(d):\(det)", settled: 2.0, file: "b88/sheet_\(v)_\(d)_\(det).jpg"))
                }
            }
        }
        list.append(Shot(name: "facts:old:0", settled: 2.0, file: "b88/facts_old.jpg"))
        list.append(Shot(name: "facts:new:0", settled: 2.0, file: "b88/facts_new_0.jpg"))
        list.append(Shot(name: "facts:new:1", settled: 2.0, file: "b88/facts_new_1.jpg"))
        list.append(Shot(name: "facts-live", motion: [4.1, 4.2, 4.3, 4.45], settled: 5.5, file: "b88/facts_live.jpg"))
        list.append(Shot(name: "profile-after", settled: 3.0, file: "b88/profile_after.jpg", scrollBottom: true))
        // Rarity sheet presented for real over the real player (Liquid Glass,
        // system grab handle, .medium detent): fixed and pre-fix.
        list.append(Shot(name: "glass:new", settled: 4.0, file: "b88/glass_new.jpg"))
        list.append(Shot(name: "glass:old", settled: 4.0, file: "b88/glass_old.jpg"))
        // The live-clock loading fixture crashes the CI test host, so only the
        // frozen frames above are captured (identical render at each offset).
        // Hidden-but-live windows from earlier shots slow later ones on the CI
        // simulator, so a run can capture just the screens it needs, in order.
        if !Self.only.isEmpty {
            return Self.only.compactMap { n in list.first { $0.name == n } }
        }
        return list
    }
    /// Shots to capture this run (empty = all).
    /// Build 88 fixes were captured with: the sheet:{old,new}:{se,promax}:{medium,large}
    /// states, facts:old:0, facts:new:0, facts:new:1, profile-after (run 44906538787);
    /// the real presented glass sheet with glass:new, glass:old (run 44909679064).
    private static let only: [String] = ["profile-after", "paywall"]

    /// Host crashes are intermittent; a crashed shot is retried (up to
    /// twice) by the next test method after xcodebuild relaunches the host.
    private func tries(_ key: String) -> Int {
        let f = Self.progressDir.appendingPathComponent("try-" + key.replacingOccurrences(of: "/", with: "_"))
        return (try? String(contentsOf: f, encoding: .utf8)).flatMap { Int($0) } ?? 0
    }
    private func setTries(_ key: String, _ n: Int) {
        try? FileManager.default.createDirectory(at: Self.progressDir, withIntermediateDirectories: true)
        let f = Self.progressDir.appendingPathComponent("try-" + key.replacingOccurrences(of: "/", with: "_"))
        try? "\(n)".write(to: f, atomically: true, encoding: .utf8)
    }

    private func run(_ shot: Shot) async {
        let key = shot.file ?? shot.name
        let n = tries(key)
        if n < 0 { return }                       // done
        if n >= 2 { step("GAVE-UP \(key)"); return }
        setTries(key, n + 1)
        await show(shot.name)
        let t0 = OnboardingParityFixtures.epoch ?? Date()
        for t in shot.motion where false {
            await spin(until: t0.addingTimeInterval(t))
            emit("motion/\(shot.name)_t\(String(format: "%05.2f", t)).jpg", settled: false)
        }
        await spin(until: t0.addingTimeInterval(shot.settled))
        emit(shot.file ?? "\(shot.name).jpg", settled: true)
        if let pvc = window?.rootViewController?.presentedViewController {
            let sheet = pvc.sheetPresentationController
            step("presented \(type(of: pvc)) frame=\(pvc.view.frame) detent=\(sheet?.selectedDetentIdentifier?.rawValue ?? "nil") grabber=\(sheet?.prefersGrabberVisible ?? false)")
        }
        if shot.scrollBottom, let root = window?.rootViewController?.view, let sv = Self.mainScrollView(in: root) {
            let maxY = max(-sv.adjustedContentInset.top,
                           sv.contentSize.height - sv.bounds.height + sv.adjustedContentInset.bottom)
            sv.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
            await spin(until: Date().addingTimeInterval(0.8))
            let base = (shot.file ?? "\(shot.name).jpg").replacingOccurrences(of: ".jpg", with: "")
            emit("\(base)_bottom.jpg", settled: true)
        }
        flush()
        setTries(key, -1)
    }

    /// The tallest vertically scrolling view (the screen's main list).
    private static func mainScrollView(in v: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ x: UIView) {
            if let sv = x as? UIScrollView, sv.contentSize.height > sv.bounds.height,
               sv.bounds.height > (best?.bounds.height ?? 0) { best = sv }
            x.subviews.forEach(walk)
        }
        walk(v)
        return best
    }

    private func runRemaining(_ pass: Int) async throws {
        try XCTSkipUnless(Self.enabled, "parity captures are off")
        step("pass \(pass)")
        if pass == 1 { dumpCrashReports() }
        let open = Self.shots.filter { let n = tries($0.file ?? $0.name); return n >= 0 && n < 2 }
        guard !open.isEmpty else { step("nothing left"); return }
        await show("probe-intro")
        await spin(until: Date().addingTimeInterval(1.0))
        if let w = window {
            print("HJSNAP-DEVICE \(UIDevice.current.name) \(UIDevice.current.systemVersion) \(w.bounds.size) scale=\(w.screen.scale) safe=\(w.safeAreaInsets)")
        }
        for shot in Self.shots { await run(shot) }
        window?.isHidden = true
        if let w = window { Self.retired.append(w) }
        window = nil
        print("HJSNAP-DONE pass \(pass)")
    }

    func testCapture01() async throws { try await runRemaining(1) }
    func testCapture02() async throws { try await runRemaining(2) }
    func testCapture03() async throws { try await runRemaining(3) }
}


/// Runs after the snapshot class (alphabetical); if that crashed, prints
/// the simulator crash report so the cause shows up in the CI log.
final class ParityCrashDumpTests: XCTestCase {
    func testDumpParityCrashReports() throws {
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ParityCapture.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path))
        let d = "/Users/runner/Library/Logs/DiagnosticReports"
        let files = (FileManager.default.subpaths(atPath: d) ?? []).filter { !$0.hasSuffix("Retired") }
        print("HJCRASH-DIR \(files.count) files")
        for f in files.sorted() {
            print("HJCRASH-NAME \(f)")
            guard f.lowercased().contains("hiddenjams") || f.hasSuffix(".ips") else { continue }
            guard let text = try? String(contentsOfFile: d + "/" + f, encoding: .utf8) else { continue }
            print("HJCRASH-FILE \(f)")
            for line in text.split(separator: "\n") { print("HJCRASH \(line.prefix(4000))") }
        }
        fflush(stdout)
    }
}
