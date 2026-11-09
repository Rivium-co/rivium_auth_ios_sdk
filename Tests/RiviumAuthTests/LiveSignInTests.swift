import XCTest
@testable import RiviumAuth

/// The ready-made sign-in screen against a real Rivium Auth server. Skipped unless these are set:
/// RIVIUM_AUTH_LIVE_KEY (a project with anonymous, password without a required confirmation and magic link on),
/// RIVIUM_AUTH_LIVE_URL, RIVIUM_AUTH_LIVE_EMAIL (a new address), RIVIUM_AUTH_LIVE_PASSWORD and
/// RIVIUM_AUTH_LIVE_MAGIC_URL (one of the project's allowed redirect URLs).
@MainActor
final class LiveSignInTests: XCTestCase {
    func testSignInScreenAgainstARealServer() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["RIVIUM_AUTH_LIVE_KEY"], !key.isEmpty,
              let url = env["RIVIUM_AUTH_LIVE_URL"].flatMap(URL.init(string:)),
              let email = env["RIVIUM_AUTH_LIVE_EMAIL"], let password = env["RIVIUM_AUTH_LIVE_PASSWORD"],
              let magic = env["RIVIUM_AUTH_LIVE_MAGIC_URL"] else {
            throw XCTSkip("RIVIUM_AUTH_LIVE_* not set")
        }
        let auth = RiviumAuth()
        auth.configure(apiKey: key, baseURL: url, urlSession: .shared, storage: MemorySessionStorage(nil))
        // The screen's language for the run, and the text expected in it.
        var language = "en"
        var wrongPassword = "Wrong e-mail or password."
        let options = RiviumSignInOptions(languageCode: language, allowGuest: true, magicLinkRedirectURL: magic)
        var signedIn: [AuthResult] = []

        // Sign up.
        let first = RiviumSignInController(auth: auth, options: options) { signedIn.append($0) }
        await first.load().value
        XCTAssertEqual(first.screen, .home, first.errorText ?? "")
        XCTAssertTrue(first.showPassword && first.showMagicLink && first.showGuest)
        XCTAssertEqual(auth.languageCode, language)
        first.go(.signUp)
        first.email = email
        first.password = password
        await first.signUp()?.value
        XCTAssertNil(first.error, first.errorText ?? "")
        let user = try XCTUnwrap(signedIn.last?.userId)
        print("signed up \(user)")
        first.close()
        XCTAssertNil(auth.languageCode, "given back on close")

        // A wrong password, in the screen's language; then the right one: the same user.
        let screen = RiviumSignInController(auth: auth, options: options) { signedIn.append($0) }
        await screen.load().value
        screen.email = email
        screen.password = password + "-wrong"
        await screen.signIn()?.value
        XCTAssertEqual(screen.error, "INVALID_CREDENTIALS")
        XCTAssertEqual(screen.errorText, wrongPassword)
        print("wrong password: \(screen.errorText ?? "")")
        screen.password = password
        await screen.signIn()?.value
        XCTAssertNil(screen.error, screen.errorText ?? "")
        XCTAssertEqual(signedIn.last?.userId, user)
        XCTAssertEqual(signedIn.count, 2)
        print("signed in again \(signedIn.last?.userId ?? "")")

        // Reset (Rivium's own page) and magic link, both in the screen's language.
        screen.go(.forgot)
        await screen.sendReset()?.value
        XCTAssertNil(screen.error, screen.errorText ?? "")
        XCTAssertEqual(screen.sent, .reset)
        print("reset sent")
        screen.go(.magicLink)
        await screen.sendMagicLink()?.value
        XCTAssertNil(screen.error, screen.errorText ?? "")
        XCTAssertEqual(screen.sent, .magicLink)
        print("magic link sent")

        // Continue as guest: a new user.
        screen.back()
        await screen.continueAsGuest()?.value
        XCTAssertNil(screen.error, screen.errorText ?? "")
        let guest = try XCTUnwrap(signedIn.last?.userId)
        XCTAssertEqual(signedIn.count, 3)
        XCTAssertNotEqual(guest, user)
        print("guest \(guest)")
        screen.close()
        XCTAssertNil(auth.languageCode)
    }
}
