#if canImport(AuthenticationServices)
import AuthenticationServices
import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension RiviumAuth {
    /// Runs the native Sign in with Apple sheet and signs the user in with the
    /// result. The nonce, the authorization code (so the Apple sign-in can be
    /// revoked on account deletion) and the name Apple shares on the first
    /// sign-in are all handled for you.
    ///
    /// Add the "Sign in with Apple" capability to your app and your bundle id
    /// to the project's Apple settings in the Rivium Console.
    ///
    /// - Parameters:
    ///   - link: Add Apple to the signed-in (for example anonymous) user instead
    ///     of signing in. Throws `.providerAlreadyLinked` when this Apple ID
    ///     belongs to another user.
    ///   - presentationAnchor: The window to show the sheet over. Defaults to
    ///     the app's key window.
    /// - Throws: `.canceled` when the user closes the sheet.
    @MainActor
    @discardableResult
    public func signInWithAppleNative(link: Bool = false, presentationAnchor: ASPresentationAnchor? = nil) async throws -> AuthResult {
        let rawNonce = RiviumNonce.generate()
        let credential = try await AppleSignInFlow(anchor: presentationAnchor ?? AppleSignInFlow.keyWindow()).run(hashedNonce: RiviumNonce.sha256(rawNonce))

        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
            throw RiviumAuthError(code: .invalidIdToken, message: "Apple returned no identity token")
        }
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        let name = credential.fullName.flatMap { components -> String? in
            let formatted = PersonNameComponentsFormatter().string(from: components)
            return formatted.isEmpty ? nil : formatted
        }
        if link {
            return try await linkApple(idToken: idToken, rawNonce: rawNonce, authorizationCode: code, fullName: name)
        }
        return try await signInWithApple(idToken: idToken, rawNonce: rawNonce, authorizationCode: code, fullName: name)
    }
}

/// One Sign in with Apple request. Keeps itself alive until Apple answers.
/// Apple calls the delegate on the main thread.
private final class AppleSignInFlow: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var keepAlive: AppleSignInFlow?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func run(hashedNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        keepAlive = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        keepAlive = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(.success(credential))
        } else {
            finish(.failure(RiviumAuthError(code: .invalidIdToken, message: "Apple returned an unexpected credential")))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let canceled = (error as? ASAuthorizationError)?.code == .canceled
        finish(.failure(RiviumAuthError(
            code: canceled ? .canceled : .invalidIdToken,
            message: canceled ? "Sign in with Apple was canceled" : "Sign in with Apple failed",
            underlying: error
        )))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    @MainActor
    static func keyWindow() -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first ?? UIWindow()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
