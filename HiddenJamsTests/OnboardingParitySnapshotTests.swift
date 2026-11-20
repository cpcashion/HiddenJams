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

    private func show(_ name: String) {
        step("show \(name)")
        // The onboarding screens only read the auth/source managers inside
        // button actions, which the captures never tap.
        let hc = UIHostingController(rootView: AnyView(OnboardingParityFixtures.screen(name)))
        hc.overrideUserInterfaceStyle = .dark
        hc.view.backgroundColor = UIColor(red: 11 / 255, green: 11 / 255, blue: 15 / 255, alpha: 1)
        if window == nil {
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            w.overrideUserInterfaceStyle = .dark
            window = w
        }
        step("window ready")
        window?.rootViewController = hc
        window?.makeKeyAndVisible()
        step("visible")
    }

    private func spin(until t: Date) {
        while Date() < t { RunLoop.main.run(until: min(t, Date().addingTimeInterval(0.01))) }
    }

    private func emit(_ file: String, settled: Bool) {
        guard let w = window else { return }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = settled ? 3 : 1.5
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(bounds: w.bounds, format: fmt).image { _ in
            _ = w.drawHierarchy(in: w.bounds, afterScreenUpdates: true)
        }
        guard let data = img.jpegData(compressionQuality: settled ? 0.92 : 0.8) else {
            print("HJSNAP-FAIL \(file)"); return
        }
        let b64 = data.base64EncodedString()
        var lines = ["HJSNAP-BEGIN \(file) \(data.count) \(Int(w.bounds.width))x\(Int(w.bounds.height))"]
        var i = 0, idx = b64.startIndex
        while idx < b64.endIndex {
            let end = b64.index(idx, offsetBy: 6000, limitedBy: b64.endIndex) ?? b64.endIndex
            lines.append("HJSNAP|\(file)|\(i)|\(b64[idx..<end])")
            idx = end; i += 1
        }
        lines.append("HJSNAP-END \(file) \(i)")
        print(lines.joined(separator: "\n"))
        fflush(stdout)
    }

    /// Shows a state, captures motion frames at each offset (s), then the settled frame.
    private func capture(_ name: String, motion: [Double], settled: Double) {
        guard attempt(name) else { return }
        defer { done(name) }
        show(name)
        let t0 = Date()
        for t in motion {
            spin(until: t0.addingTimeInterval(t))
            emit("motion/\(name)_t\(String(format: "%05.2f", t)).jpg", settled: false)
        }
        spin(until: t0.addingTimeInterval(settled))
        emit("\(name).jpg", settled: true)
    }

    func testCaptureOnboardingParity() throws {
        try XCTSkipUnless(Self.enabled, "parity captures are off")
        step("begin")
        dumpCrashReports()
        for probe in ["probe-flow", "probe-onb"] where attempt(probe) {
            show(probe)
            spin(until: Date().addingTimeInterval(0.6))
            step("ok \(probe)")
            done(probe)
        }
        show("probe-intro")
        spin(until: Date().addingTimeInterval(1.5))
        step("first spin done")
        if let w = window {
            print("HJSNAP-DEVICE \(UIDevice.current.name) \(UIDevice.current.systemVersion) \(w.bounds.size) scale=\(w.screen.scale) safe=\(w.safeAreaInsets)")
        }
        // Same names, offsets and settle times as shoot_proto_device.py.
        capture("01-intro", motion: [0.4, 0.8, 1.2, 1.6, 2.0, 2.6, 3.4], settled: 6.0)
        capture("02-keep", motion: [0.5, 0.9, 1.1, 1.3, 1.5, 1.7, 1.9, 2.2, 2.6, 3.0, 3.5, 4.0, 5.0, 6.0, 7.5], settled: 8.6)
        capture("03-rarity", motion: [0.3, 0.6, 0.9, 1.2, 1.6, 2.0, 2.6, 3.4], settled: 5.0)
        capture("04a-mood-none", motion: [0.3], settled: 2.0)
        capture("04-mood", motion: [], settled: 2.0)
        capture("05-connect", motion: [0.4, 1.2, 2.0], settled: 3.5)
        capture("06-loading", motion: [0.3, 0.8, 1.5, 2.5, 3.4, 4.2, 5.2, 6.5, 7.8], settled: 8.7)
        capture("06-loading-apple", motion: [4.2], settled: 8.7)
        capture("06-loading-empty", motion: [1.0, 2.2], settled: 4.1)
        capture("07-genres", motion: [0.2, 0.5, 0.8], settled: 3.0)
        capture("08-rarity", motion: [0.2, 0.5, 0.9, 1.4], settled: 3.0)
        capture("09-artists", motion: [0.3, 0.6], settled: 3.0)
        capture("10-deepest", motion: [0.3, 0.6], settled: 3.0)
        capture("10-deepest-spotify", motion: [], settled: 3.0)
        capture("10-deepest-nopicks", motion: [], settled: 3.0)
        capture("11-fresh", motion: [0.3], settled: 3.0)
        capture("11-fresh-nopicks", motion: [], settled: 3.0)
        window?.isHidden = true
        window = nil
        print("HJSNAP-DONE")
    }
}


/// Runs after the snapshot class (alphabetical); if that crashed, prints
/// the simulator crash report so the cause shows up in the CI log.
final class ParityCrashDumpTests: XCTestCase {
    func testDumpParityCrashReports() throws {
        let marker = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ParityCapture.enabled")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: marker.path))
        let d = "/Users/runner/Library/Logs/DiagnosticReports"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? []
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
