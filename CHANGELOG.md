# Changelog

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
