# Changelog

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
