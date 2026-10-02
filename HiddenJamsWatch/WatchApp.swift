//
//  WatchApp.swift
//  HiddenJamsWatch
//
//  Apple Watch remote for Hidden Jams: thumbs down on the left, thumbs up
//  on the right. Thumbs up saves the currently-playing gem (same as a
//  swipe right on iPhone); thumbs down skips to the next one.
//

import SwiftUI

@main
struct HiddenJamsWatchApp: App {
    @StateObject private var bridge = WatchBridge()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bridge)
        }
    }
}
