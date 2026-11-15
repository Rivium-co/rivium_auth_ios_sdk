<p align="center">
  <a href="https://rivium.co">
    <img src="https://rivium.co/icon.svg" alt="Rivium" width="120" />
  </a>
</p>

<h3 align="center">Rivium Auth iOS SDK</h3>

<p align="center">
  Sign-in for your iOS and macOS app's users: anonymous, Apple, Google, e-mail and password, magic link and Telegram, with a user token every Rivium SDK accepts.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.7+-F05138?logo=swift&logoColor=white" alt="Swift 5.7+" />
  <img src="https://img.shields.io/badge/iOS-13.0+-000000?logo=apple&logoColor=white" alt="iOS 13+" />
  <img src="https://img.shields.io/badge/macOS-12.0+-000000?logo=apple&logoColor=white" alt="macOS 12+" />
  <img src="https://img.shields.io/badge/SPM-compatible-orange" alt="SPM Compatible" />
  <img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="MIT License" />
</p>

---

## Installation

### Swift Package Manager (SPM)

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Rivium-co/rivium_auth_ios_sdk.git", from: "0.5.0"),
]
```

Then add `"RiviumAuth"` to your target's dependencies. Or in Xcode: **File > Add Package Dependencies** and enter:

```
https://github.com/Rivium-co/rivium_auth_ios_sdk.git
```

### CocoaPods

```ruby
pod 'RiviumAuth', '~> 0.5'
```

## Quick start

Turn Rivium Auth on for your project in the Rivium Console and enable the
sign-in methods you want. Then, at app start:

```swift
import RiviumAuth

RiviumAuth.shared.configure(apiKey: "rv_live_YOUR_PUBLIC_KEY")
```

A session from an earlier launch is restored automatically.

```swift
try await RiviumAuth.shared.signInAnonymously()
print(RiviumAuth.shared.currentUserId ?? "signed out")
```

## Ready-made sign-in screen

Like FirebaseUI: Rivium's sign-in screen, with no forms to build. It shows only the methods turned on in the Console
and answers the signed-in user, or nil when the user closed it (iOS 15 and later).

```swift
import RiviumAuth

let options = RiviumSignInOptions(appName: "My Shop")
if let result = await RiviumSignIn.present(from: self, options: options) {
    print(result.userId)
}
```

It opens full screen on iPhone and as a sheet on iPad, and cannot be closed while a sign-in runs. There is also a
completion-handler version, `RiviumSignIn.present(from:options:completion:)`. To put the form in a SwiftUI screen of
your own, use `RiviumSignInView(options: options) { result in ... }`.

| Option | What it does |
|---|---|
| `appName`, `logo` | The title ("Sign in to My Shop") and an image above it |
| `languageCode` | The language of the e-mails sent from the screen (the screen itself is in English). Default: the app's language. Ignored when you set `languageCode` on the client yourself |
| `allowGuest` | Shows "Continue as guest" when anonymous sign-in is on. Off by default: every guest is a new user and counts toward your plan |
| `google`, `apple` | A function that gets an ID token for the hashed nonce it is given (for example with Google Sign-In). The button shows only when you pass it. `apple: RiviumSignInOptions.nativeApple` runs Sign in with Apple for you |
| `magicLinkRedirectURL` | A link that opens your app; shows the magic link button. Finish it with `signInWithMagicLink(url:)` |
| `verifyRedirectURL`, `resetRedirectURL` | Your own pages for the confirm and reset links. Default: Rivium's pages |
| `continueURL` | Where the "Continue" button of Rivium's confirm and reset pages takes the user afterwards (for example your website). One of the project's link addresses |
| `openURL` | Opens the Telegram bot link (for example `{ await UIApplication.shared.open($0) }`); without it the link is shown to copy |

When the project requires a confirmed e-mail and the user signs in before confirming, the screen shows "Send again":
it e-mails a new confirmation link, using the e-mail and password just typed.

The screen follows your app's tint colour and dark mode.

## Sign in

```swift
let auth = RiviumAuth.shared

try await auth.signInAnonymously()
try await auth.signIn(email: "ana@example.com", password: "a-long-password")
let result = try await auth.signUp(email: "ana@example.com", password: "a-long-password",
                                   redirectURL: "https://example.com/verify")
try await auth.sendPasswordReset(email: "ana@example.com") // the link opens Rivium's reset page

// Magic link: send it, then sign in with the link the app is opened with.
try await auth.sendMagicLink(email: "ana@example.com", redirectURL: "https://example.com/magic")
try await auth.signInWithMagicLink(url: openedURL)

// Telegram: the code arrives in the project's bot.
let code = try await auth.requestTelegramCode(phone: "+37491234567")
if !code.sent, let url = code.botURL { await UIApplication.shared.open(url) }
try await auth.verifyTelegramCode(phone: "+37491234567", code: "123456")
```

### Confirm the e-mail

When the project requires a confirmed e-mail (Console › Rivium Auth › Settings), `signUp` always sends the
confirmation link (to Rivium's own confirm page when you pass no `redirectURL`) and the user is signed in only after
confirming. For someone who signs in before confirming (the error is `.emailNotVerified`), send the link again with
the e-mail and password they typed. It does not sign them in:

```swift
do {
    try await auth.signIn(email: email, password: password)
} catch let error as RiviumAuthError where error.code == .emailNotVerified {
    try await auth.resendVerification(email: email, password: password)
}
```

A wrong password fails like signing in (`.invalidCredentials`); an account that is already confirmed gets no e-mail.
A signed-in user who has not confirmed yet gets a new link with `sendEmailVerification()`.

### Continue after the link

`signUp`, `sendPasswordReset`, `sendEmailVerification` and `resendVerification` take an optional `continueURL`, like
Firebase's continue URL: after confirming the e-mail or saving the new password on Rivium's own page, the user sees a
"Continue" button that goes there. It must be one of the project's link addresses (Console › Rivium Auth › Settings),
otherwise the call fails with `.invalidInput`. It is not used when `redirectURL` is your own page.

```swift
try await auth.sendPasswordReset(email: "ana@example.com", continueURL: "https://example.com/welcome-back")
```

Link addresses may also be `http://localhost:<port>` or `http://127.0.0.1:<port>` while you develop.

Show only the methods the project offers:

```swift
let methods = try await auth.getMethods()
if methods.isEnabled("apple") { /* show the Apple button */ }
```

### Sign in with Apple

Add the **Sign in with Apple** capability to your app and your bundle id to
the project's Apple settings in the Console. Then:

```swift
try await RiviumAuth.shared.signInWithAppleNative()
```

If you run the Apple request yourself, use a nonce:

```swift
let rawNonce = RiviumNonce.generate()
request.nonce = RiviumNonce.sha256(rawNonce)   // to Apple
// ... when Apple answers:
try await auth.signInWithApple(idToken: idToken, rawNonce: rawNonce,
                               authorizationCode: code, fullName: name)
```

Pass the authorization code: it lets the Apple sign-in be revoked when the
user deletes the account.

### Sign in with Google

Request the Google ID token with `RiviumNonce.sha256(rawNonce)` as its nonce,
then pass the raw nonce to Rivium. The nonce is required (16-256 characters;
`RiviumNonce.generate()` makes one) and works once:

```swift
let rawNonce = RiviumNonce.generate()
// Google Sign-In: nonce = RiviumNonce.sha256(rawNonce)
try await auth.signInWithGoogle(idToken: idToken, rawNonce: rawNonce)
```

## Upgrade an anonymous user

Linking keeps the user's id, so everything they created stays theirs:

```swift
do {
    try await auth.linkGoogle(idToken: idToken, rawNonce: rawNonce)
    // or linkApple(...), linkPassword(email:password:)
} catch let error as RiviumAuthError where error.code == .providerAlreadyLinked {
    // This Google account already belongs to another user.
}
```

## Use with other Rivium SDKs

Rivium Sync, Chat and Push trust the signed-in user through a token provider:

```swift
let auth = RiviumAuth.shared

// Sync
sync.userTokens.provider = auth.tokenProvider

// Push
RiviumPushConfig(apiKey: key, tokenProvider: auth.tokenProvider)

// Chat
RiviumChatConfig(apiKey: key, userId: auth.currentUserId!, tokenProvider: auth.strictTokenProvider)
```

`tokenProvider` returns nil when nobody is signed in; `strictTokenProvider`
throws instead. Both return a token that is refreshed before it expires.

## Session

```swift
auth.currentUserId                  // nil when signed out
let user = try await auth.me()      // profile: anonymous, providers, ...

let listener = auth.addAuthStateListener { userId in
    // called on sign-in, sign-out and when a session ends
}
listener.remove()

await auth.signOut()                // this device
try await auth.signOutEverywhere()  // every device
try await auth.deleteAccount()      // required by the App Store for apps with sign-in
```

The refresh token is stored in the Keychain on this device only; the access
token stays in memory. A session revoked elsewhere signs the user out here; a
network error does not.

## Custom claims

Your server sets custom claims for a user with the server secret (`setCustomUserClaims`, see
[Custom claims](https://rivium.co/docs/auth/custom-claims)), for example `{ "plan": "pro" }`. Every token of the
user carries them, and Rivium Sync rules read them as `auth.token.plan`. In the app, read them to show things
(a "Pro" badge): access is still decided on the server.

```swift
let result = try await auth.getTokenResult()
if result?.claims["plan"] as? String == "pro" { showProBadge() }

// Right after your server changed the claims ("Check my purchase"):
_ = try await auth.getTokenResult(forceRefresh: true)
```

## E-mail language

Confirm e-mail, password reset and magic-link e-mails go out in the language you set, like Firebase's `languageCode`.
Unset, the project's template language from the Console applies. Edit the texts in **Console › Rivium Auth › Email
templates**.

```swift
RiviumAuth.shared.languageCode = "de" // or RiviumAuth.shared.useAppLanguage()
```

See [Email templates](https://rivium.co/docs/auth/email-templates).

## Errors

Every error is a `RiviumAuthError`. Branch on `code` (for example
`.invalidCredentials`, `.emailTaken`, `.weakPassword`, `.rateLimited` with
`retryAfterSec`, `.providerAlreadyLinked`); `message` is an English hint for
developers.

## Example app

[`Example/`](Example) is a SwiftUI app with the ready-made sign-in screen,
anonymous sign-in, e-mail sign-up and sign-in, sign-out and account deletion. Open
`Example/RiviumAuthExample.xcodeproj`, run it on a simulator and paste your
public key (`rv_live_...`) into its API key field. The project is generated
from `Example/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Documentation

- [Rivium Auth Docs](https://rivium.co/cloud/rivium-auth/docs)
- [iOS SDK guide](https://rivium.co/cloud/rivium-auth/docs/sdks-ios)

## Support

- **Documentation**: [Rivium Auth Docs](https://rivium.co/cloud/rivium-auth/docs)
- **Issues**: [GitHub Issues](https://github.com/Rivium-co/rivium_auth_ios_sdk/issues)
- **Email**: support@rivium.co

## License

MIT License — see [LICENSE](LICENSE) for details.
