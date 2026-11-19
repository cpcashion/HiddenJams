//
//  OnboardingSnapshotHooks.swift
//  HiddenJams
//
//  TOOLING ONLY (branch tooling/onboarding-screenshots, never merged).
//  DEBUG-only hook so the parity snapshot test can open OnboardingView on a
//  given page. Release builds compile none of this.
//

#if DEBUG
enum OnboardingSnapshotHooks {
    /// Initial page for OnboardingView (0 = normal behaviour).
    static var introPage = 0
}
#endif
