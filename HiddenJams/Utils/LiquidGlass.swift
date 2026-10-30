//
//  LiquidGlass.swift
//  HiddenJams
//
//  Subtle iOS 26 Liquid Glass for interactive controls (build 78).
//
//  The app's palette (lime, pastels, plum) stays exactly as designed: the
//  solid brand color sits directly behind a glass layer tinted with the
//  same color. The glass adds the Liquid Glass rim light, lensing, and
//  (when interactive) the press/bounce response — it never replaces the
//  color. Per Apple's guidance, glass goes on controls (buttons, pills,
//  chips, tab bar, transport controls, the slider thumb), not on content
//  cards.
//
//  Deployment target is iOS 26.0+, so glassEffect / GlassEffectContainer
//  are always available — no #available fallback needed.
//

import SwiftUI

extension View {
    /// Brand-colored Liquid Glass for a control.
    /// - Parameters:
    ///   - color: The control's existing fill (e.g. `Theme.Colors.lime`).
    ///   - shape: The control's shape.
    ///   - interactive: Adds the iOS 26 touch response (scale + shimmer).
    ///     Pass false when the glass element sits inside a larger button.
    func brandGlass<S: Shape>(_ color: Color, in shape: S, interactive: Bool = true) -> some View {
        let tint = color.opacity(0.55)
        return self
            .glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint), in: shape)
            .background(shape.fill(color))
    }

    /// Clear (untinted) interactive glass for secondary icon controls that
    /// had no fill before, e.g. skip buttons.
    func subtleGlass<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular.interactive(), in: shape)
    }
}
