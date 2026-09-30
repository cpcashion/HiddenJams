//
//  ThemeManager.swift
//  HiddenJams
//
//  App-wide appearance mode (dark / light). The light theme is monochrome
//  with blue accents; the dark theme keeps the signature gold "hidden gems"
//  look. Persisted across launches.
//

import SwiftUI
import Combine

enum AppTheme: String, CaseIterable {
    case dark
    case light

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var iconName: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let storageKey = "appTheme"

    @Published var mode: AppTheme {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.storageKey)
        }
    }

    var isLight: Bool { mode == .light }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey) ?? AppTheme.dark.rawValue
        self.mode = AppTheme(rawValue: raw) ?? .dark
    }
}
