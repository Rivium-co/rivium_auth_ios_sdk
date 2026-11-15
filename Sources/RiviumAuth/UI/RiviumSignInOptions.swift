import Foundation
import SwiftUI

/// What Sign in with Apple returned.
public struct RiviumAppleCredential: Equatable {
    public let idToken: String
    /// Lets Rivium revoke the Apple sign-in when the account is deleted.
    public let authorizationCode: String?
    /// The name Apple gives on the first sign-in only.
    public let fullName: String?

    public init(idToken: String, authorizationCode: String? = nil, fullName: String? = nil) {
        self.idToken = idToken
        self.authorizationCode = authorizationCode
        self.fullName = fullName
    }
}

/// What the sign-in screen offers and how it looks. Every method also has to be turned on in the Console
/// (Rivium Auth › Sign-in methods).
public struct RiviumSignInOptions {
    /// Shown as "Sign in to `appName`". nil: "Sign in".
    public var appName: String?

    /// Shown above the title, for example your app icon (`Image("AppLogo")` or `Image(uiImage: image)`).
    public var logo: Image?

    /// The screen's language, a code such as `en`. nil: the app's language, English when the screen doesn't have it.
    /// The e-mails Rivium sends follow it too, unless you set `RiviumAuth.languageCode` yourself.
    public var languageCode: String?

    /// Shows "Continue as guest" when anonymous sign-in is on. Off by default: every guest is a new user and counts
    /// toward the plan's monthly users.
    public var allowGuest: Bool

    /// Gets a Google ID token for the hashed nonce it is given, with your Google sign-in (for example GoogleSignIn's
    /// `nonce:`). Return nil when the user cancels. Shows "Continue with Google" when Google sign-in is on.
    public var google: ((_ hashedNonce: String) async throws -> String?)?

    /// Runs Sign in with Apple for the hashed nonce it is given. Return nil when the user cancels. Shows
    /// "Continue with Apple" when Apple sign-in is on. `RiviumSignInOptions.nativeApple` runs Apple's own sheet.
    public var apple: ((_ hashedNonce: String) async throws -> RiviumAppleCredential?)?

    /// One of the project's allowed redirect URLs that opens your app. Shows the magic link button when set and
    /// magic link is on. Your app finishes it with `RiviumAuth.shared.signInWithMagicLink(url:)`.
    public var magicLinkRedirectURL: String?

    /// Where the confirm e-mail link goes. nil: Rivium's own confirm page.
    public var verifyRedirectURL: String?

    /// Where the password reset link goes. nil: Rivium's own reset page.
    public var resetRedirectURL: String?

    /// Where the "Continue" button of Rivium's own confirm and reset pages takes the user afterwards, for example
    /// your website. One of the project's link addresses (Console › Rivium Auth › Settings). nil: no such button.
    public var continueURL: String?

    /// Opens the Telegram bot link, for example `{ await UIApplication.shared.open($0) }`. Without it the screen
    /// shows the link for the user to copy.
    public var openURL: ((URL) async -> Void)?

    public init(
        appName: String? = nil,
        logo: Image? = nil,
        languageCode: String? = nil,
        allowGuest: Bool = false,
        google: ((_ hashedNonce: String) async throws -> String?)? = nil,
        apple: ((_ hashedNonce: String) async throws -> RiviumAppleCredential?)? = nil,
        magicLinkRedirectURL: String? = nil,
        verifyRedirectURL: String? = nil,
        resetRedirectURL: String? = nil,
        continueURL: String? = nil,
        openURL: ((URL) async -> Void)? = nil
    ) {
        self.appName = appName
        self.logo = logo
        self.languageCode = languageCode
        self.allowGuest = allowGuest
        self.google = google
        self.apple = apple
        self.magicLinkRedirectURL = magicLinkRedirectURL
        self.verifyRedirectURL = verifyRedirectURL
        self.resetRedirectURL = resetRedirectURL
        self.continueURL = continueURL
        self.openURL = openURL
    }
}
