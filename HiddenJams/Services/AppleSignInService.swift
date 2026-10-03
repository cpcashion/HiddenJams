//
//  AppleSignInService.swift
//  HiddenJams
//
//  Sign in with Apple — the verified identity for Apple Music users.
//  MusicKit tells us nothing about who the user is, so this is what
//  turns an anonymous Apple Music listener into a real user profile
//  (needed for subscriptions, sync, and support).
//
//  NOTE: the App ID needs the "Sign in with Apple" capability enabled in
//  the Apple Developer portal, and the provisioning profile must include
//  it. The HiddenJams.entitlements file declares it client-side.
//

import AuthenticationServices
import Foundation
import UIKit

enum AppleSignInError: Error, LocalizedError {
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Sign in was cancelled."
        case .failed(let msg): return msg
        }
    }
}

final class AppleSignInService: NSObject {
    static let shared = AppleSignInService()

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    private override init() { super.init() }

    /// Presents the Sign in with Apple sheet. Returns the credential on
    /// success. Callers link it via UserProfileManager.linkAppleID.
    @MainActor
    func signIn() async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = [.fullName, .email]
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Quietly checks whether the linked Apple ID credential is still valid
    /// (e.g. the user revoked it in Settings).
    func credentialState(for userIdentifier: String) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { cont in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userIdentifier) { state, _ in
                cont.resume(returning: state)
            }
        }
    }
}

extension AppleSignInService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.failed("Unexpected credential type."))
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            continuation?.resume(throwing: AppleSignInError.cancelled)
        } else {
            continuation?.resume(throwing: AppleSignInError.failed(error.localizedDescription))
        }
        continuation = nil
    }
}

extension AppleSignInService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Key window of the active scene.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first?.windows.first { $0.isKeyWindow } ?? UIWindow()
    }
}
