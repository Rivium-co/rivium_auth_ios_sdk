import Foundation

/// A token provider in the shape Rivium Sync and Rivium Push accept:
/// the signed-in user's token, or nil when nobody is signed in.
public typealias RiviumAuthTokenProvider = () async throws -> String?

/// A token provider in the shape Rivium Chat accepts: the signed-in user's
/// token, or an error (`.notSignedIn`) when nobody is signed in.
public typealias RiviumAuthStrictTokenProvider = () async throws -> String

/// A listener registration. Call `remove()` to stop receiving changes.
public final class RiviumAuthListener {
    private let onRemove: () -> Void
    init(onRemove: @escaping () -> Void) { self.onRemove = onRemove }
    public func remove() { onRemove() }
}

/// Rivium Auth: sign-in for your app's users.
///
/// ```swift
/// RiviumAuth.shared.configure(apiKey: "rv_live_...")
/// try await RiviumAuth.shared.signInAnonymously()
///
/// // Other Rivium SDKs trust the signed-in user through the token provider:
/// sync.userTokens.provider = RiviumAuth.shared.tokenProvider
/// ```
///
/// The refresh token is kept in the Keychain and the access token in memory.
/// The SDK refreshes the access token about two minutes before it expires.
public final class RiviumAuth {
    public static let shared = RiviumAuth()

    public static let defaultBaseURL = URL(string: "https://auth-users.rivium.co")!

    private let lock = NSLock()
    private var http: HTTPClient?
    private var session: SessionManager?
    private var userId: String?
    private var cachedUser: RiviumUser?
    private var listeners: [UUID: (String?) -> Void] = [:]
    private var language: String?

    init() {}

    // MARK: - Language

    /// The language of the e-mails Rivium sends this user (confirm e-mail, password reset, magic link), like
    /// Firebase's `languageCode`: a BCP 47 tag such as `de` or `en-US`. nil = the project's template language
    /// (Console › Rivium Auth › Email templates). A language Rivium has no texts for also falls back to it.
    public var languageCode: String? {
        get {
            lock.lock(); defer { lock.unlock() }
            return language
        }
        set {
            let v = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ok = (2...35).contains(v.count) && v.range(of: "^[A-Za-z]{2,8}([-_][A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil
            lock.lock()
            language = ok ? v : nil
            http?.locale = language
            lock.unlock()
        }
    }

    /// Sets `languageCode` to the app's current language, like Firebase's `useAppLanguage()`.
    public func useAppLanguage() {
        languageCode = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first
    }

    // MARK: - Setup

    /// Sets the project's public API key. Call once, at app start, before any
    /// other call. A session saved by an earlier launch is restored.
    ///
    /// - Parameters:
    ///   - apiKey: The public project key (`rv_live_...`).
    ///   - baseURL: Only for testing against another Rivium Auth server.
    ///   - keychainAccessGroup: Share the session with your app extensions.
    public func configure(apiKey: String, baseURL: URL = RiviumAuth.defaultBaseURL, keychainAccessGroup: String? = nil) {
        let storage = KeychainSessionStorage(apiKey: apiKey, accessGroup: keychainAccessGroup)
        Self.forgetSessionFromPreviousInstall(storage)
        configure(apiKey: apiKey, baseURL: baseURL, urlSession: .shared, storage: storage)
    }

    /// Keychain items outlive an uninstall; a fresh install starts signed out.
    private static func forgetSessionFromPreviousInstall(_ storage: SessionStorage) {
        let key = "co.rivium.auth.installed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        storage.clear()
        UserDefaults.standard.set(true, forKey: key)
    }

    func configure(apiKey: String, baseURL: URL, urlSession: URLSession, storage: SessionStorage, now: @escaping () -> Date = Date.init) {
        let http = HTTPClient(baseURL: baseURL, apiKey: apiKey, session: urlSession)
        let manager = SessionManager(http: http, storage: storage, now: now) { [weak self] user in
            self?.userChanged(user)
        }
        lock.lock()
        http.locale = language
        self.http = http
        self.session = manager
        self.userId = manager.restoredUserId
        self.cachedUser = nil
        lock.unlock()
    }

    /// The Rivium Auth server this client talks to.
    public var baseURL: URL {
        lock.lock(); defer { lock.unlock() }
        return http?.baseURL ?? Self.defaultBaseURL
    }

    // MARK: - State

    /// The signed-in user's id, or nil.
    public var currentUserId: String? {
        lock.lock(); defer { lock.unlock() }
        return userId
    }

    public var isSignedIn: Bool { currentUserId != nil }

    /// The profile last loaded by `me()` for the signed-in user, or nil.
    public var currentUser: RiviumUser? {
        lock.lock(); defer { lock.unlock() }
        return cachedUser?.id == userId ? cachedUser : nil
    }

    /// Called with the user id on every sign-in, sign-out and session end
    /// (including a session revoked on the server), on the main queue. Also
    /// called once right away with the current user.
    @discardableResult
    public func addAuthStateListener(_ listener: @escaping (String?) -> Void) -> RiviumAuthListener {
        let id = UUID()
        lock.lock()
        listeners[id] = listener
        let current = userId
        lock.unlock()
        DispatchQueue.main.async { listener(current) }
        return RiviumAuthListener { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.listeners[id] = nil
            self.lock.unlock()
        }
    }

    private func userChanged(_ user: String?) {
        lock.lock()
        userId = user
        if cachedUser?.id != user { cachedUser = nil }
        let targets = Array(listeners.values)
        lock.unlock()
        DispatchQueue.main.async { targets.forEach { $0(user) } }
    }

    // MARK: - Tokens

    /// The signed-in user's access token, refreshed when it is about to
    /// expire. Nil when nobody is signed in.
    public func getAccessToken(forceRefresh: Bool = false) async throws -> String? {
        try await sessionManager().validAccessToken(forceRefresh: forceRefresh)
    }

    /// The access token with its decoded fields, like Firebase's
    /// `getIDTokenResult()`: `claims` holds the custom claims your server set
    /// (`setCustomUserClaims`), for example to show a "Pro" badge. Nil when
    /// nobody is signed in. Pass `forceRefresh: true` right after your server
    /// changed the claims, to get them without waiting for the next refresh
    /// (at most an hour). For display only: access is decided on the server.
    public func getTokenResult(forceRefresh: Bool = false) async throws -> RiviumTokenResult? {
        guard let token = try await getAccessToken(forceRefresh: forceRefresh) else { return nil }
        return RiviumTokenResult(token: token)
    }

    /// Pass this to Rivium Sync and Rivium Push: `sync.userTokens.provider = RiviumAuth.shared.tokenProvider`.
    public var tokenProvider: RiviumAuthTokenProvider {
        { [unowned self] in try await self.getAccessToken() }
    }

    /// Pass this to Rivium Chat: `RiviumChatConfig(..., tokenProvider: RiviumAuth.shared.strictTokenProvider)`.
    public var strictTokenProvider: RiviumAuthStrictTokenProvider {
        { [unowned self] in
            guard let token = try await self.getAccessToken() else { throw RiviumAuthError.notSignedIn }
            return token
        }
    }

    // MARK: - Anonymous

    @discardableResult
    public func signInAnonymously() async throws -> AuthResult {
        try await start(client().send("POST", "v1/anonymous", as: SessionTokens.self))
    }

    // MARK: - Apple / Google

    /// Signs in with an Apple ID token. The token's nonce must be
    /// `RiviumNonce.sha256(rawNonce)`. Pass `authorizationCode` so the
    /// Apple sign-in can be revoked when the user deletes the account, and
    /// `fullName` on the first sign-in (Apple sends it only once).
    @discardableResult
    public func signInWithApple(idToken: String, rawNonce: String, authorizationCode: String? = nil, fullName: String? = nil) async throws -> AuthResult {
        let body = Self.social(idToken, rawNonce, authorizationCode, fullName)
        return try await start(client().send("POST", "v1/apple", body: body, as: SessionTokens.self))
    }

    /// Signs in with a Google ID token requested with the nonce
    /// `RiviumNonce.sha256(rawNonce)`. `rawNonce` (16-256 characters) is
    /// required: Rivium Auth refuses a Google sign-in without it.
    @discardableResult
    public func signInWithGoogle(idToken: String, rawNonce: String) async throws -> AuthResult {
        let body = Self.social(idToken, rawNonce, nil, nil)
        return try await start(client().send("POST", "v1/google", body: body, as: SessionTokens.self))
    }

    /// Adds Apple to the signed-in user (typically an anonymous one, which keeps
    /// its id and data). Throws `.providerAlreadyLinked` when this Apple ID
    /// belongs to another user.
    @discardableResult
    public func linkApple(idToken: String, rawNonce: String, authorizationCode: String? = nil, fullName: String? = nil) async throws -> AuthResult {
        let body = Self.social(idToken, rawNonce, authorizationCode, fullName)
        return try await link("v1/link/apple", body)
    }

    /// Adds Google to the signed-in user. Throws `.providerAlreadyLinked` when
    /// this Google account belongs to another user. `rawNonce` works as in
    /// `signInWithGoogle(idToken:rawNonce:)`.
    @discardableResult
    public func linkGoogle(idToken: String, rawNonce: String) async throws -> AuthResult {
        try await link("v1/link/google", Self.social(idToken, rawNonce, nil, nil))
    }

    private static func social(_ idToken: String, _ nonce: String, _ code: String?, _ name: String?) -> [String: String] {
        var body = ["idToken": idToken, "nonce": nonce]
        body["authorizationCode"] = code
        body["name"] = name
        return body
    }

    // MARK: - E-mail and password

    /// Creates an account. When the project requires a verified e-mail the
    /// user is not signed in until they follow the link (`signedIn == false`),
    /// and the confirmation e-mail is always sent (to Rivium's own page when
    /// there is no `redirectURL`).
    /// - Parameters:
    ///   - redirectURL: Where the verification link opens; one of the
    ///     project's link addresses.
    ///   - continueURL: Where the "Continue" button of Rivium's own confirm page
    ///     takes the user afterwards (Firebase's continue URL); one of the
    ///     project's link addresses. Not used when `redirectURL` is your own page.
    public func signUp(email: String, password: String, redirectURL: String? = nil, continueURL: String? = nil) async throws -> SignUpResult {
        var body = ["email": email, "password": password]
        body["redirectUrl"] = redirectURL
        body["continueUrl"] = continueURL
        let response = try await client().send("POST", "v1/password/sign-up", body: body, as: SignUpResponse.self)
        if let session = response.session { try await start(session) }
        return SignUpResult(userId: response.userId, verificationSent: response.verificationSent ?? false, signedIn: response.session != nil)
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> AuthResult {
        try await start(client().send("POST", "v1/password/sign-in", body: ["email": email, "password": password], as: SessionTokens.self))
    }

    /// Gives the signed-in (typically anonymous) user an e-mail and password,
    /// keeping its id. Throws `.emailTaken` when the address has an account.
    @discardableResult
    public func linkPassword(email: String, password: String) async throws -> AuthResult {
        try await link("v1/link/password", ["email": email, "password": password])
    }

    /// Sends a password-reset link. Succeeds whether or not the address has an account.
    /// - Parameters:
    ///   - redirectURL: Where the link opens; one of the project's link addresses. nil: Rivium's own reset page.
    ///   - continueURL: Where the "Continue" button of Rivium's reset page takes the user after saving the new
    ///     password; one of the project's link addresses. Not used when `redirectURL` is your own page.
    public func sendPasswordReset(email: String, redirectURL: String? = nil, continueURL: String? = nil) async throws {
        var body = ["email": email]
        body["redirectUrl"] = redirectURL
        body["continueUrl"] = continueURL
        try await client().send("POST", "v1/password/forgot", body: body)
    }

    /// Sets a new password with the token from the reset link. Every session of
    /// the user ends; the user then signs in with the new password.
    public func resetPassword(token: String, newPassword: String) async throws {
        try await client().send("POST", "v1/password/reset", body: ["token": token, "password": newPassword])
    }

    /// Confirms the e-mail with the token from the verification link.
    public func verifyEmail(token: String) async throws {
        try await client().send("POST", "v1/email/verify", body: ["token": token])
    }

    /// Sends the signed-in user a new verification link.
    /// - Parameters:
    ///   - redirectURL: Where the link opens; one of the project's link addresses. nil: Rivium's own confirm page.
    ///   - continueURL: Where the "Continue" button of Rivium's confirm page takes the user afterwards; one of the
    ///     project's link addresses. Not used when `redirectURL` is your own page.
    public func sendEmailVerification(redirectURL: String? = nil, continueURL: String? = nil) async throws {
        var body: [String: String] = [:]
        body["redirectUrl"] = redirectURL
        body["continueUrl"] = continueURL
        try await authorized { http, token in
            try await http.send("POST", "v1/email/send-verification", body: body, bearer: token)
        }
    }

    /// Sends the confirmation e-mail again to someone who can't sign in yet because the project requires a
    /// verified e-mail (`signIn` failed with `.emailNotVerified`). The e-mail and password prove the account: a wrong
    /// pair fails like signing in (`.invalidCredentials`). Nothing is sent to an account that is already confirmed.
    /// Does not sign in and does not change who is signed in.
    /// - Parameters:
    ///   - redirectURL: Where the link opens; one of the project's link addresses. nil: Rivium's own confirm page.
    ///   - continueURL: Where the "Continue" button of Rivium's confirm page takes the user afterwards; one of the
    ///     project's link addresses. Not used when `redirectURL` is your own page.
    public func resendVerification(email: String, password: String, redirectURL: String? = nil, continueURL: String? = nil) async throws {
        var body = ["email": email, "password": password]
        body["redirectUrl"] = redirectURL
        body["continueUrl"] = continueURL
        try await client().send("POST", "v1/email/resend-verification", body: body)
    }

    // MARK: - Magic link

    /// E-mails a sign-in link. Succeeds whether or not the address has an account.
    public func sendMagicLink(email: String, redirectURL: String) async throws {
        try await client().send("POST", "v1/magic-link/send", body: ["email": email, "redirectUrl": redirectURL])
    }

    /// Signs in with the token from a magic link. The account is created on first use.
    @discardableResult
    public func signInWithMagicLink(token: String) async throws -> AuthResult {
        try await start(client().send("POST", "v1/magic-link/consume", body: ["token": token], as: SessionTokens.self))
    }

    /// Signs in with the link the app was opened with (reads its `token` parameter).
    @discardableResult
    public func signInWithMagicLink(url: URL) async throws -> AuthResult {
        guard let token = Self.token(in: url) else {
            throw RiviumAuthError(code: .invalidInput, message: "The link has no token")
        }
        return try await signInWithMagicLink(token: token)
    }

    /// The `token` query parameter of a reset, verification or magic link.
    public static func token(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "token" }?.value
    }

    // MARK: - Telegram

    /// Asks for a sign-in code in Telegram. When `sent` is false, open
    /// `botURL` so the user starts the bot and shares their phone; the code
    /// then arrives there.
    /// - Parameter phone: International format, e.g. "+37491234567".
    public func requestTelegramCode(phone: String) async throws -> TelegramCodeResult {
        let r = try await client().send("POST", "v1/telegram/code", body: ["phone": phone], as: TelegramCodeResponse.self)
        return TelegramCodeResult(sent: r.sent, botURL: r.botUrl.flatMap(URL.init(string:)), expiresIn: r.expiresIn ?? 300)
    }

    @discardableResult
    public func verifyTelegramCode(phone: String, code: String) async throws -> AuthResult {
        try await start(client().send("POST", "v1/telegram/verify", body: ["phone": phone, "code": code], as: SessionTokens.self))
    }

    // MARK: - Project and user

    /// The sign-in methods this project offers.
    public func getMethods() async throws -> AuthMethods {
        let r = try await client().send("GET", "v1/methods", as: MethodsResponse.self)
        return AuthMethods(methods: r.methods, telegramBot: r.telegramBot)
    }

    /// Loads the signed-in user's profile (also kept as `currentUser`).
    public func me() async throws -> RiviumUser {
        let user = try await authorized { http, token in
            RiviumUser(try await http.send("GET", "v1/me", bearer: token, as: PublicUserResponse.self))
        }
        cache(user)
        return user
    }

    private func cache(_ user: RiviumUser) {
        lock.lock(); defer { lock.unlock() }
        if user.id == userId { cachedUser = user }
    }

    // MARK: - Sign-out and deletion

    /// Signs out on this device. Never fails: the session is forgotten locally
    /// even when the server cannot be reached.
    public func signOut() async {
        guard let manager = session, let http = http else { return }
        guard let refreshToken = await manager.clear() else { return }
        try? await http.send("POST", "v1/sign-out", body: ["refreshToken": refreshToken])
    }

    /// Ends every session of the user, on every device, then signs out here.
    public func signOutEverywhere() async throws {
        try await authorized { http, token in
            try await http.send("POST", "v1/sign-out-everywhere", bearer: token)
        }
        await (try sessionManager()).clear()
    }

    /// Deletes the user and everything Rivium Auth holds about them, then signs
    /// out. Apple requires apps with sign-in to offer this.
    public func deleteAccount() async throws {
        try await authorized { http, token in
            try await http.send("DELETE", "v1/me", bearer: token)
        }
        await (try sessionManager()).clear()
    }

    // MARK: - Internals

    private func client() throws -> HTTPClient {
        lock.lock(); defer { lock.unlock() }
        guard let http = http else { throw RiviumAuthError.sdkNotConfigured }
        return http
    }

    private func sessionManager() throws -> SessionManager {
        lock.lock(); defer { lock.unlock() }
        guard let session = session else { throw RiviumAuthError.sdkNotConfigured }
        return session
    }

    /// Starts the session a sign-in returned and ends the one it replaces.
    @discardableResult
    private func start(_ tokens: SessionTokens) async throws -> AuthResult {
        let manager = try sessionManager()
        let http = try client()
        if let replaced = await manager.adopt(tokens) {
            // The previous session (for example the anonymous one just upgraded)
            // is no longer reachable from this device: end it on the server.
            Task { try? await http.send("POST", "v1/sign-out", body: ["refreshToken": replaced]) }
        }
        return AuthResult(userId: tokens.userId, isNewUser: tokens.created)
    }

    private func link(_ path: String, _ body: [String: String]) async throws -> AuthResult {
        let tokens = try await authorized { http, token in
            try await http.send("POST", path, body: body, bearer: token, as: SessionTokens.self)
        }
        return try await start(tokens)
    }

    /// Runs a signed-in call; when the server refuses the access token, gets a
    /// fresh one and tries once more.
    private func authorized<T>(_ call: (HTTPClient, String) async throws -> T) async throws -> T {
        let http = try client()
        let manager = try sessionManager()
        guard let token = try await manager.validAccessToken() else { throw RiviumAuthError.notSignedIn }
        do {
            return try await call(http, token)
        } catch let error as RiviumAuthError where error.httpStatus == 401 && (error.code == .unauthenticated || error.code == .tokenInvalid) {
            guard let fresh = try await manager.validAccessToken(forceRefresh: true) else { throw RiviumAuthError.notSignedIn }
            return try await call(http, fresh)
        }
    }
}
