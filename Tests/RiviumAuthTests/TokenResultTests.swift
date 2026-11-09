import XCTest
@testable import RiviumAuth

/// getTokenResult: Firebase's AuthTokenResult, from a token shaped like the ones Rivium signs.
final class TokenResultTests: XCTestCase {
    private let now = 1_793_000_000

    private func jwt(_ payload: [String: Any]) -> String {
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let body = try! JSONSerialization.data(withJSONObject: payload)
        return "\(b64(Data(#"{"alg":"ES256","typ":"JWT"}"#.utf8))).\(b64(body)).c2ln"
    }

    private func standard(iat: Int? = nil) -> [String: Any] {
        let iat = iat ?? now
        return ["iss": "rivium", "aud": "rivium_user", "sub": "ru_user1", "pid": "p1", "iat": iat, "exp": iat + 3600,
                "auth_time": now - 86400, "amr": ["google"], "meta": ["pid": "p1", "srv": true, "iat": iat]]
    }

    func testDecodesEveryFieldFlatWithCustomClaimsAndNoMeta() {
        var p = standard()
        p["plan"] = "pro"
        p["team"] = ["id": "t1", "tags": ["red"]]
        p["نقش"] = "مدیر 👋"
        let r = RiviumTokenResult(token: jwt(p))!
        XCTAssertEqual(r.claims["plan"] as? String, "pro")
        XCTAssertEqual((r.claims["team"] as? [String: Any])?["id"] as? String, "t1")
        XCTAssertEqual(r.claims["نقش"] as? String, "مدیر 👋")
        XCTAssertEqual(r.claims["sub"] as? String, "ru_user1")
        XCTAssertNil(r.claims["meta"])
        XCTAssertEqual(r.expirationDate, Date(timeIntervalSince1970: TimeInterval(now + 3600)))
        XCTAssertEqual(r.issuedAtDate, Date(timeIntervalSince1970: TimeInterval(now)))
        XCTAssertEqual(r.authDate, Date(timeIntervalSince1970: TimeInterval(now - 86400)))
        XCTAssertEqual(r.signInProvider, "google")
    }

    func testBrokenTokensGiveNilAndOldTokensFallBackToIssueTime() {
        XCTAssertNil(RiviumTokenResult(token: "one-part"))
        XCTAssertNil(RiviumTokenResult(token: "a.!!!.c"))
        XCTAssertNil(RiviumTokenResult(token: jwt(["sub": "x"])))
        var old = standard()
        old.removeValue(forKey: "auth_time")
        XCTAssertEqual(RiviumTokenResult(token: jwt(old))!.authDate, Date(timeIntervalSince1970: TimeInterval(now)))
    }

    func testFromTheClientForceRefreshGetsNewClaimsAtOnce() async throws {
        var plan = "free"
        StubURLProtocol.reset { [self] _ in
            var p = standard(iat: Int(Date().timeIntervalSince1970))
            p["plan"] = plan
            return .json(200, sessionBody(access: jwt(p), refresh: "ref-1", user: "ru_user1"))
        }
        let auth = RiviumAuth()
        auth.configure(apiKey: "rv_live_test", baseURL: URL(string: "https://auth.test")!, urlSession: StubURLProtocol.session(), storage: MemorySessionStorage(nil))
        let signedOut = try await auth.getTokenResult()
        XCTAssertNil(signedOut)
        _ = try await auth.signInAnonymously()
        let first = try await auth.getTokenResult()
        XCTAssertEqual(first?.claims["plan"] as? String, "free")
        plan = "pro" // the developer's server changed the claims
        let cached = try await auth.getTokenResult()
        XCTAssertEqual(cached?.claims["plan"] as? String, "free", "the same token until it is refreshed")
        let fresh = try await auth.getTokenResult(forceRefresh: true)
        XCTAssertEqual(fresh?.claims["plan"] as? String, "pro")
    }

    func testNestedCustomClaimsFromTheRiviumServerComeOutByNameAndTokenFieldsWin() {
        var p = standard()
        p.removeValue(forKey: "auth_time")
        p["claims"] = ["levels": ["A1"], "sub": "someone-else"]
        let r = RiviumTokenResult(token: jwt(p))!
        XCTAssertEqual(r.claims["levels"] as? [String], ["A1"])
        XCTAssertEqual(r.claims["sub"] as? String, "ru_user1")
        XCTAssertNil(r.claims["claims"])
        XCTAssertEqual(r.authDate, r.issuedAtDate)
    }
}
