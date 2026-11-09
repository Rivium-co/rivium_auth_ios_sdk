import Foundation

/// The access token with its decoded fields, like Firebase's `AuthTokenResult`.
///
/// For display only (a "Pro" badge, unlocked lessons): the app can read the
/// token but never change it. Rivium's servers check the token on every
/// request and decide access with rules.
public struct RiviumTokenResult {
    /// The access token itself (the same one `getAccessToken()` gives).
    public let token: String
    /// Every field of the token: `sub` (the user id), `pid`, `iss`, `aud`,
    /// `iat`, `exp`, `auth_time`, `amr`, and the custom claims your server set
    /// with `setCustomUserClaims` (for example `plan`, `role`). Objects are
    /// dictionaries, lists are arrays, JSON null is `NSNull`.
    public let claims: [String: Any]
    /// When this token expires.
    public let expirationDate: Date
    /// When this token was issued.
    public let issuedAtDate: Date
    /// When the user signed in: the session's start; a refresh doesn't change it.
    public let authDate: Date
    /// How the user signed in: `anonymous`, `apple`, `google`, `password`,
    /// `magic_link`, `telegram`.
    public let signInProvider: String?

    /// Reads a token; nil when it isn't one Rivium signs.
    public init?(token: String) {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let object = try? JSONSerialization.jsonObject(with: data),
              var payload = object as? [String: Any],
              let exp = (payload["exp"] as? NSNumber)?.doubleValue,
              let iat = (payload["iat"] as? NSNumber)?.doubleValue
        else { return nil }
        let amr = (payload["amr"] as? [Any])?.first as? String
        let authTime = (payload["auth_time"] as? NSNumber)?.doubleValue ?? iat
        payload.removeValue(forKey: "meta") // Rivium's own bookkeeping for its servers, not a claim
        self.token = token
        self.claims = payload
        self.expirationDate = Date(timeIntervalSince1970: exp)
        self.issuedAtDate = Date(timeIntervalSince1970: iat)
        self.authDate = Date(timeIntervalSince1970: authTime)
        self.signInProvider = amr
    }
}
