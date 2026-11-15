# Changelog

## 0.5.0

- `resendVerification(email:password:redirectURL:continueURL:)`: sends the confirmation e-mail again to someone who
  can't sign in yet because the project requires a confirmed e-mail (`signIn` failed with `.emailNotVerified`). The
  e-mail and password prove the account; a wrong pair fails like signing in (`.invalidCredentials`). It does not sign
  in, and an account that is already confirmed gets no e-mail.
- `continueURL` (optional) on `signUp`, `sendPasswordReset`, `sendEmailVerification` and `resendVerification`, like
  Firebase's continue URL: Rivium's own confirm and reset pages then show a "Continue" button that takes the user
  there. It must be one of the project's link addresses (Console › Rivium Auth › Settings).
- `sendEmailVerification()`: `redirectURL` is optional; without it the link opens Rivium's own confirm page.
- Projects that require a confirmed e-mail: `signUp` now always sends the confirmation e-mail, also without
  `redirectURL` (the link then opens Rivium's own confirm page), so `verificationSent` is true.
- Link addresses may be `http://localhost:<port>` or `http://127.0.0.1:<port>` while you develop.
- Ready-made sign-in screen: when signing in fails because the e-mail is not confirmed, it shows "Send again", which
  e-mails a new confirmation link and then says "We sent a new link to {email}." New option `continueURL`, used for
  creating an account, forgot password and "Send again".

## 0.2.0

- `getTokenResult(forceRefresh:)`: the access token with its decoded fields, like Firebase's `AuthTokenResult`.
  `claims` holds the custom claims your server set with `setCustomUserClaims` (for example `plan`, `role`), plus
  `sub`, `iat`, `exp`, `auth_time` and `amr`; also `expirationDate`, `issuedAtDate`, `authDate` and `signInProvider`.
  For showing things in the app; access is still decided on the server. Pass `forceRefresh: true` right after your
  server changed the claims.

## 0.1.1

- Sends `X-Rivium-SDK: auth-ios/0.1.1` with every request so Rivium can show
  which SDK versions are in use. No behaviour change.

## 0.1.0

- First release.
- Sign-in methods: anonymous, Apple, Google, e-mail and password, magic link
  and Telegram code.
- Upgrade an anonymous user with `linkApple`, `linkGoogle` and
  `linkPassword`; the user keeps its id.
- `signInWithAppleNative()` runs Sign in with Apple, nonce included.
- `rawNonce` is required for Apple and Google sign-in and linking.
- The refresh token is kept in the Keychain (this device only); the access
  token stays in memory and is refreshed before it expires, one refresh at a
  time.
- `tokenProvider` and `strictTokenProvider` plug straight into the other
  Rivium SDKs.
- `signOut()`, `signOutEverywhere()`, `deleteAccount()` and an auth state
  listener.
