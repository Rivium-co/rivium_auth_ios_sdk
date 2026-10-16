import Foundation

/// Owns the session: the refresh token (persisted) and the access token
/// (memory only). Refreshes are single-flight: however many callers ask for a
/// token at once, one refresh request goes out and all of them get its result.
actor SessionManager {
    /// Refresh this long before the access token actually expires.
    static let refreshSkew: TimeInterval = 120

    private let http: HTTPClient
    private let storage: SessionStorage
    private let now: () -> Date
    private let onUserChange: (String?) -> Void

    private var refreshToken: String?
    private var userId: String?
    private var accessToken: String?
    private var accessExpiry: Date = .distantPast
    private var inflight: Task<String?, Error>?
    /// Bumped whenever the session is replaced or ended, so a refresh that
    /// finishes late never overwrites a newer session.
    private var generation = 0

    /// The user restored from storage at start-up.
    nonisolated let restoredUserId: String?

    init(http: HTTPClient, storage: SessionStorage, now: @escaping () -> Date = Date.init, onUserChange: @escaping (String?) -> Void) {
        self.http = http
        self.storage = storage
        self.now = now
        self.onUserChange = onUserChange
        let stored = storage.load()
        self.refreshToken = stored?.refreshToken
        self.userId = stored?.userId
        self.restoredUserId = stored?.userId
    }

    var currentUserId: String? { userId }

    /// Starts a session from a sign-in response. Returns the refresh token of
    /// the session it replaced, so the caller can end that one on the server.
    @discardableResult
    func adopt(_ tokens: SessionTokens) -> String? {
        let previous = refreshToken
        storage.save(StoredSession(refreshToken: tokens.refreshToken, userId: tokens.userId))
        generation += 1
        inflight = nil
        refreshToken = tokens.refreshToken
        accessToken = tokens.accessToken
        accessExpiry = now().addingTimeInterval(tokens.expiresIn)
        setUser(tokens.userId)
        return previous == tokens.refreshToken ? nil : previous
    }

    /// Ends the session locally. Returns its refresh token, if there was one.
    @discardableResult
    func clear() -> String? {
        let previous = refreshToken
        storage.clear()
        generation += 1
        inflight = nil
        refreshToken = nil
        accessToken = nil
        accessExpiry = .distantPast
        setUser(nil)
        return previous
    }

    /// A valid access token, refreshing when it is missing or about to expire.
    ///
    /// - Returns: nil when nobody is signed in, or when the session just ended
    ///   (revoked, expired, user disabled): the user is then signed out.
    /// - Throws: on network or server errors; the session is kept.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String? {
        if !forceRefresh, let token = accessToken, accessExpiry.timeIntervalSince(now()) > Self.refreshSkew {
            return token
        }
        if let running = inflight { return try await running.value }
        guard refreshToken != nil else { return nil }

        let gen = generation
        let task = Task { try await self.refresh(generation: gen) }
        inflight = task
        defer { if generation == gen { inflight = nil } }
        return try await task.value
    }

    private func refresh(generation gen: Int) async throws -> String? {
        guard let sent = refreshToken else { return nil }
        do {
            let tokens = try await http.send("POST", "v1/token/refresh", body: ["refreshToken": sent], as: SessionTokens.self)
            guard generation == gen else { return accessToken } // Replaced meanwhile; keep the newer session.
            // Persist the rotated refresh token first: the old one is already burned.
            storage.save(StoredSession(refreshToken: tokens.refreshToken, userId: tokens.userId))
            refreshToken = tokens.refreshToken
            accessToken = tokens.accessToken
            accessExpiry = now().addingTimeInterval(tokens.expiresIn)
            setUser(tokens.userId)
            return tokens.accessToken
        } catch let error as RiviumAuthError where error.endsSession {
            guard generation == gen else { return accessToken }
            // Another process sharing this Keychain entry (an app extension) may
            // have rotated the token already: use its newer one once.
            if error.code == .tokenInvalid, let stored = storage.load(), stored.refreshToken != sent {
                refreshToken = stored.refreshToken
                return try await refresh(generation: gen)
            }
            clear()
            return nil
        } catch {
            guard generation == gen else { return accessToken }
            // Offline or a server hiccup: keep the session; an access token that
            // has not actually expired yet still works.
            if let token = accessToken, accessExpiry > now() { return token }
            throw error
        }
    }

    private func setUser(_ newUser: String?) {
        guard userId != newUser else { return }
        userId = newUser
        onUserChange(newUser)
    }
}
