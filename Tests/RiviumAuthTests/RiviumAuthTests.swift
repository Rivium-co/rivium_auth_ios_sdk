import XCTest
@testable import RiviumAuth

final class RiviumAuthTests: XCTestCase {
    private var auth: RiviumAuth!
    private var storage: MemorySessionStorage!
    private let base = URL(string: "https://auth.test")!

    private func make(restored: StoredSession? = nil) {
        storage = MemorySessionStorage(restored)
        auth = RiviumAuth()
        auth.configure(apiKey: "rv_live_test", baseURL: base, urlSession: StubURLProtocol.session(), storage: storage)
    }

    // MARK: - Sign-in

    func testSignInStoresTokens() async throws {
        StubURLProtocol.reset { r in
            r.path == "/v1/anonymous" ? .json(200, sessionBody(access: "acc-1", refresh: "ref-1", user: "u-anon")) : .empty(500)
        }
        make()

        let result = try await auth.signInAnonymously()

        XCTAssertEqual(result.userId, "u-anon")
        XCTAssertEqual(storage.load(), StoredSession(refreshToken: "ref-1", userId: "u-anon"))
        XCTAssertEqual(auth.currentUserId, "u-anon")
        let token = try await auth.getAccessToken()
        XCTAssertEqual(token, "acc-1")
        XCTAssertEqual(StubURLProtocol.requests.count, 1, "a fresh access token is served from memory")
        XCTAssertEqual(StubURLProtocol.requests[0].headers["x-api-key"], "rv_live_test")
    }

    func testRestoredSessionIsSignedInWithoutNetwork() {
        StubURLProtocol.reset { _ in .empty(500) }
        make(restored: StoredSession(refreshToken: "ref-0", userId: "u-1"))
        XCTAssertEqual(auth.currentUserId, "u-1")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - Single-flight refresh

    func testConcurrentTokenRequestsShareOneRefresh() async throws {
        StubURLProtocol.reset { r in
            r.path == "/v1/token/refresh" ? .json(200, sessionBody(access: "acc-2", refresh: "ref-2", user: "u-1"), delay: 0.3) : .empty(500)
        }
        make(restored: StoredSession(refreshToken: "ref-1", userId: "u-1"))

        let tokens = try await withThrowingTaskGroup(of: String?.self) { group -> [String?] in
            for _ in 0..<8 { group.addTask { try await self.auth.getAccessToken() } }
            var all: [String?] = []
            for try await t in group { all.append(t) }
            return all
        }

        XCTAssertEqual(tokens, Array(repeating: "acc-2", count: 8))
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/token/refresh").count, 1)
    }

    func testTwoProvidersAtOnceRefreshOnce() async throws {
        StubURLProtocol.reset { r in
            r.path == "/v1/token/refresh" ? .json(200, sessionBody(access: "acc-2", refresh: "ref-2", user: "u-1"), delay: 0.2) : .empty(500)
        }
        make(restored: StoredSession(refreshToken: "ref-1", userId: "u-1"))
        let sync: () async throws -> String? = auth.tokenProvider
        let chat: () async throws -> String = auth.strictTokenProvider

        async let a = sync()
        async let b = chat()
        let (ta, tb) = try await (a, b)

        XCTAssertEqual(ta, "acc-2")
        XCTAssertEqual(tb, "acc-2")
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/token/refresh").count, 1)
    }

    // MARK: - Rotation

    func testRefreshRotationSavesNewRefreshToken() async throws {
        var issued = 1
        StubURLProtocol.reset { r in
            guard r.path == "/v1/token/refresh" else { return .empty(500) }
            issued += 1
            return .json(200, sessionBody(access: "acc-\(issued)", refresh: "ref-\(issued)", user: "u-1"))
        }
        make(restored: StoredSession(refreshToken: "ref-1", userId: "u-1"))

        let first = try await auth.getAccessToken()
        XCTAssertEqual(first, "acc-2")
        XCTAssertEqual(storage.load()?.refreshToken, "ref-2")

        let second = try await auth.getAccessToken(forceRefresh: true)
        XCTAssertEqual(second, "acc-3")
        XCTAssertEqual(storage.load()?.refreshToken, "ref-3")

        let sent = StubURLProtocol.requests(to: "/v1/token/refresh").map { $0.body["refreshToken"] as? String }
        XCTAssertEqual(sent, ["ref-1", "ref-2"], "each refresh presents the newest token")
    }

    func testRefreshesBeforeExpiry() async throws {
        var calls = 0
        StubURLProtocol.reset { r in
            switch r.path {
            case "/v1/anonymous": return .json(200, sessionBody(access: "acc-short", refresh: "ref-1", expiresIn: 100))
            case "/v1/token/refresh":
                calls += 1
                return .json(200, sessionBody(access: "acc-new", refresh: "ref-2"))
            default: return .empty(500)
            }
        }
        make()
        try await auth.signInAnonymously()

        // 100 s left is inside the 2-minute window: refresh now.
        let token = try await auth.getAccessToken()
        XCTAssertEqual(token, "acc-new")
        XCTAssertEqual(calls, 1)
    }

    // MARK: - Session end

    func testRevokedSessionSignsOut() async throws {
        StubURLProtocol.reset { r in
            r.path == "/v1/token/refresh"
                ? .json(401, ["code": "SESSION_REVOKED", "message": "Session ended, sign in again"])
                : .empty(500)
        }
        make(restored: StoredSession(refreshToken: "ref-1", userId: "u-1"))
        let signedOut = expectation(description: "listener told about sign-out")
        var seen: [String?] = []
        auth.addAuthStateListener { user in
            seen.append(user)
            if seen.count == 2 { signedOut.fulfill() }
        }

        let token = try await auth.getAccessToken()

        XCTAssertNil(token)
        XCTAssertNil(storage.load())
        XCTAssertNil(auth.currentUserId)
        await fulfillment(of: [signedOut], timeout: 2)
        XCTAssertEqual(seen, ["u-1", nil])
    }

    func testStrictProviderThrowsWhenSignedOut() async {
        StubURLProtocol.reset { _ in .empty(500) }
        make()
        do {
            _ = try await auth.strictTokenProvider()
            XCTFail("expected notSignedIn")
        } catch let error as RiviumAuthError {
            XCTAssertEqual(error.code, .notSignedIn)
        } catch {
            XCTFail("unexpected \(error)")
        }
        let token = try? await auth.tokenProvider()
        XCTAssertNil(token ?? nil)
    }

    func testNetworkErrorKeepsSession() async {
        StubURLProtocol.reset { _ in .failure(.notConnectedToInternet) }
        make(restored: StoredSession(refreshToken: "ref-1", userId: "u-1"))
        do {
            _ = try await auth.getAccessToken()
            XCTFail("expected a network error")
        } catch let error as RiviumAuthError {
            XCTAssertEqual(error.code, .network)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(storage.load()?.refreshToken, "ref-1")
        XCTAssertEqual(auth.currentUserId, "u-1")
    }

    func testSignOutClearsLocallyAndEndsServerSession() async throws {
        StubURLProtocol.reset { r in
            r.path == "/v1/anonymous" ? .json(200, sessionBody(access: "a", refresh: "ref-1")) : .empty(204)
        }
        make()
        try await auth.signInAnonymously()
        await auth.signOut()

        XCTAssertNil(storage.load())
        XCTAssertNil(auth.currentUserId)
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/sign-out").first?.body["refreshToken"] as? String, "ref-1")
    }

    // MARK: - Linking and errors

    func testLinkProviderAlreadyLinkedIsTyped() async throws {
        StubURLProtocol.reset { r in
            switch r.path {
            case "/v1/anonymous": return .json(200, sessionBody(access: "acc-1", refresh: "ref-1", user: "u-anon"))
            case "/v1/link/google": return .json(409, ["code": "PROVIDER_ALREADY_LINKED", "message": "This account is already used by another user"])
            default: return .empty(500)
            }
        }
        make()
        try await auth.signInAnonymously()
        let nonce = RiviumNonce.generate()

        do {
            try await auth.linkGoogle(idToken: "id", rawNonce: nonce)
            XCTFail("expected PROVIDER_ALREADY_LINKED")
        } catch let error as RiviumAuthError where error.code == .providerAlreadyLinked {
            XCTAssertEqual(error.httpStatus, 409)
        }
        XCTAssertEqual(auth.currentUserId, "u-anon")
        XCTAssertEqual(storage.load()?.refreshToken, "ref-1")
        let link = StubURLProtocol.requests(to: "/v1/link/google")[0]
        XCTAssertEqual(link.headers["Authorization"], "Bearer acc-1")
        XCTAssertEqual(link.body["nonce"] as? String, nonce)
    }

    func testGoogleSignInSendsTheRawNonce() async throws {
        StubURLProtocol.reset { r in
            r.path == "/v1/google" ? .json(200, sessionBody(access: "acc-1", refresh: "ref-1", user: "u-g")) : .empty(500)
        }
        make()
        let raw = RiviumNonce.generate()
        let result = try await auth.signInWithGoogle(idToken: "g.id.token", rawNonce: raw)

        XCTAssertEqual(result.userId, "u-g")
        let body = StubURLProtocol.requests(to: "/v1/google")[0].body
        XCTAssertEqual(body["idToken"] as? String, "g.id.token")
        XCTAssertEqual(body["nonce"] as? String, raw)
    }

    func testLinkReplacesSessionAndEndsTheOldOne() async throws {
        StubURLProtocol.reset { r in
            switch r.path {
            case "/v1/anonymous": return .json(200, sessionBody(access: "acc-1", refresh: "ref-anon", user: "u-1"))
            case "/v1/link/apple": return .json(200, sessionBody(access: "acc-2", refresh: "ref-apple", user: "u-1"))
            default: return .empty(204)
            }
        }
        make()
        try await auth.signInAnonymously()
        let result = try await auth.linkApple(idToken: "id", rawNonce: "n0123456789abcdef", authorizationCode: "code")

        XCTAssertEqual(result.userId, "u-1")
        XCTAssertEqual(storage.load()?.refreshToken, "ref-apple")
        let body = StubURLProtocol.requests(to: "/v1/link/apple")[0].body
        XCTAssertEqual(body["nonce"] as? String, "n0123456789abcdef")
        XCTAssertEqual(body["authorizationCode"] as? String, "code")

        // The anonymous session's refresh token is ended in the background.
        for _ in 0..<50 where StubURLProtocol.requests(to: "/v1/sign-out").isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/sign-out").first?.body["refreshToken"] as? String, "ref-anon")
    }

    func testRateLimitedCarriesRetryAfter() async {
        StubURLProtocol.reset { _ in .json(429, ["code": "RATE_LIMITED", "message": "Too many attempts", "retryAfterSec": 42]) }
        make()
        do {
            try await auth.signIn(email: "a@b.co", password: "secret-pass")
            XCTFail("expected RATE_LIMITED")
        } catch let error as RiviumAuthError {
            XCTAssertEqual(error.code, .rateLimited)
            XCTAssertEqual(error.retryAfterSec, 42)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testSignedInCallRetriesOnceWithFreshToken() async throws {
        var meCalls = 0
        StubURLProtocol.reset { r in
            switch r.path {
            case "/v1/anonymous": return .json(200, sessionBody(access: "stale", refresh: "ref-1", user: "u-1"))
            case "/v1/token/refresh": return .json(200, sessionBody(access: "fresh", refresh: "ref-2", user: "u-1"))
            case "/v1/me":
                meCalls += 1
                if r.headers["Authorization"] == "Bearer stale" { return .json(401, ["code": "UNAUTHENTICATED", "message": "Sign-in required"]) }
                return .json(200, ["id": "u-1", "anonymous": true, "emailVerified": false, "createdAt": "2026-10-16T10:00:00.000Z", "providers": []])
            default: return .empty(500)
            }
        }
        make()
        try await auth.signInAnonymously()
        let user = try await auth.me()

        XCTAssertEqual(user.id, "u-1")
        XCTAssertTrue(user.isAnonymous)
        XCTAssertNotNil(user.createdAt)
        XCTAssertEqual(meCalls, 2)
        XCTAssertEqual(auth.currentUser, user)
    }

    func testSignUpWithoutSessionStaysSignedOut() async throws {
        StubURLProtocol.reset { _ in .json(200, ["userId": "u-9", "verificationSent": true, "session": NSNull()]) }
        make()
        let result = try await auth.signUp(email: "a@b.co", password: "long-password-1", redirectURL: "myapp://verify")
        XCTAssertEqual(result, SignUpResult(userId: "u-9", verificationSent: true, signedIn: false))
        XCTAssertNil(auth.currentUserId)
    }

    func testMethodsAndTelegram() async throws {
        StubURLProtocol.reset { r in
            switch r.path {
            case "/v1/methods": return .json(200, ["methods": ["anonymous", "telegram"], "telegramBot": "my_bot"])
            case "/v1/telegram/code": return .json(200, ["sent": false, "botUrl": "https://t.me/my_bot?start=signin", "expiresIn": 300])
            default: return .empty(500)
            }
        }
        make()
        let methods = try await auth.getMethods()
        XCTAssertTrue(methods.isEnabled("telegram"))
        XCTAssertEqual(methods.telegramBot, "my_bot")
        let code = try await auth.requestTelegramCode(phone: "+37491234567")
        XCTAssertFalse(code.sent)
        XCTAssertEqual(code.botURL?.host, "t.me")
    }

    func testNotConfigured() async {
        let fresh = RiviumAuth()
        do {
            try await fresh.signInAnonymously()
            XCTFail("expected sdkNotConfigured")
        } catch let error as RiviumAuthError {
            XCTAssertEqual(error.code, .sdkNotConfigured)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Nonce

    func testNonce() {
        let raw = RiviumNonce.generate()
        XCTAssertEqual(raw.count, 32)
        XCTAssertNotEqual(raw, RiviumNonce.generate())
        XCTAssertEqual(RiviumNonce.sha256("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testMagicLinkTokenFromURL() {
        XCTAssertEqual(RiviumAuth.token(in: URL(string: "myapp://auth?token=abc123&x=1")!), "abc123")
        XCTAssertNil(RiviumAuth.token(in: URL(string: "myapp://auth")!))
    }
}
