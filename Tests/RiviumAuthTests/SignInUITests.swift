import XCTest
@testable import RiviumAuth

/// The ready-made sign-in screen's controller against a fake Rivium Auth server.
@MainActor
final class SignInUITests: XCTestCase {
    private let base = URL(string: "https://auth.example.test")!
    private var answers: [String: (StubURLProtocol.Recorded) -> StubURLProtocol.Reply] = [:]
    private var methods: [String] = []
    private var bot: String?

    override func setUp() async throws {
        answers = [:]
        methods = []
        bot = nil
        StubURLProtocol.reset { [unowned self] r in
            if r.path == "/v1/methods" {
                var body: [String: Any] = ["methods": self.methods]
                body["telegramBot"] = self.bot
                return .json(200, body)
            }
            return self.answers[r.path]?(r) ?? .json(404, ["code": "NOT_FOUND", "message": "no"])
        }
    }

    private func client() -> RiviumAuth {
        let auth = RiviumAuth()
        auth.configure(apiKey: "rv_live_test", baseURL: base, urlSession: StubURLProtocol.session(), storage: MemorySessionStorage(nil))
        return auth
    }

    /// A loaded screen and what it reported.
    private func screen(_ methods: [String], _ options: RiviumSignInOptions = RiviumSignInOptions(languageCode: "en"), auth: RiviumAuth? = nil) async -> (RiviumSignInController, () -> [AuthResult]) {
        self.methods = methods
        var signedIn: [AuthResult] = []
        let c = RiviumSignInController(auth: auth ?? client(), options: options) { signedIn.append($0) }
        await c.load().value
        return (c, { signedIn })
    }

    private func session(_ user: String) -> StubURLProtocol.Reply {
        .json(200, sessionBody(access: "acc-\(user)", refresh: "ref-\(user)", user: user))
    }

    private func bodies(_ path: String) -> [[String: Any]] {
        StubURLProtocol.requests(to: path).map(\.body)
    }

    private func en(_ options: (inout RiviumSignInOptions) -> Void) -> RiviumSignInOptions {
        var o = RiviumSignInOptions(languageCode: "en")
        options(&o)
        return o
    }

    // MARK: - Rule 1: methods

    func testShowsOnlyTheMethodsThatAreOnAndThatTheAppCanRun() async {
        let all = ["password", "anonymous", "magicLink", "telegram", "google", "apple"]
        let (bare, _) = await screen(all)
        XCTAssertEqual(bare.screen, .home)
        XCTAssertTrue(bare.showPassword)
        XCTAssertTrue(bare.showTelegram)
        XCTAssertFalse(bare.showGoogle, "no Google function from the app")
        XCTAssertFalse(bare.showApple, "no Apple function from the app")
        XCTAssertFalse(bare.showMagicLink, "no magic link URL from the app")
        XCTAssertFalse(bare.showGuest, "guest is off by default")

        let (full, _) = await screen(all, en {
            $0.allowGuest = true
            $0.google = { _ in "id" }
            $0.apple = { _ in RiviumAppleCredential(idToken: "id") }
            $0.magicLinkRedirectURL = "myapp://magic"
        })
        XCTAssertTrue(full.showGoogle && full.showApple && full.showMagicLink && full.showGuest)

        let (off, _) = await screen(["password"], en {
            $0.allowGuest = true
            $0.google = { _ in "id" }
            $0.magicLinkRedirectURL = "myapp://magic"
        })
        XCTAssertFalse(off.showGoogle || off.showMagicLink || off.showGuest || off.hasOtherMethods, "methods turned off stay hidden")
    }

    func testNoPasswordMethodNoEmailForm() async {
        let (c, _) = await screen(["telegram"])
        XCTAssertEqual(c.screen, .home)
        XCTAssertFalse(c.showPassword)
        XCTAssertTrue(c.hasOtherMethods)
    }

    func testNothingOnSaysSignInIsNotAvailableWithRetry() async {
        let (c, _) = await screen(["anonymous"]) // guest not allowed by the app
        XCTAssertEqual(c.screen, .unavailable)
        XCTAssertNil(c.errorText)
        XCTAssertEqual(c.strings["noMethods"], "Sign-in is not available right now.")
        methods = ["password"]
        await c.load().value
        XCTAssertEqual(c.screen, .home)
    }

    func testNoAnswerFromTheServerShowsTheNetworkMessageAndTryAgainWorks() async {
        StubURLProtocol.reset { _ in .failure(.notConnectedToInternet) }
        let c = RiviumSignInController(auth: client(), options: RiviumSignInOptions(languageCode: "en"))
        await c.load().value
        XCTAssertEqual(c.screen, .unavailable)
        XCTAssertEqual(c.errorText, "No connection. Check your internet and try again.")
        XCTAssertEqual(c.strings["retry"], "Try again")

        StubURLProtocol.reset { _ in .json(200, ["methods": ["password"]]) }
        await c.load().value
        XCTAssertEqual(c.screen, .home)
        XCTAssertNil(c.errorText)
    }

    // MARK: - Rule 2: field checks

    func testFieldChecksBeforeAnyRequest() async {
        let (c, _) = await screen(["password"])
        XCTAssertNil(c.signIn())
        XCTAssertEqual(c.emailError, "Required")
        XCTAssertEqual(c.passwordError, "Required")
        c.email = "not-an-email"
        c.password = "x"
        XCTAssertNil(c.signIn())
        XCTAssertEqual(c.emailError, "Enter a valid e-mail")
        XCTAssertNil(c.passwordError)
        c.go(.forgot)
        c.email = " "
        XCTAssertNil(c.sendReset())
        XCTAssertEqual(c.emailError, "Required")
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/v1/methods"], "nothing sent")
    }

    // MARK: - Sign-in and errors (rule 8)

    func testEmailSignInCallsTheSDKAndReportsTheUser() async {
        answers["/v1/password/sign-in"] = { _ in self.session("u1") }
        let (c, signedIn) = await screen(["password"])
        c.email = "  ana@example.com "
        c.password = "a-good-password"
        await c.signIn()?.value
        XCTAssertEqual(bodies("/v1/password/sign-in").first as? [String: String], ["email": "ana@example.com", "password": "a-good-password"])
        XCTAssertEqual(signedIn().map(\.userId), ["u1"])
        XCTAssertEqual(c.password, "", "the password is not kept after a sign-in")
        XCTAssertEqual(c.auth.currentUserId, "u1")
    }

    func testWrongPasswordShowsAMessageFromTheCodeNotTheServerHint() async {
        answers["/v1/password/sign-in"] = { _ in .json(401, ["code": "INVALID_CREDENTIALS", "message": "hint for developers"]) }
        let (c, signedIn) = await screen(["password"])
        c.email = "ana@example.com"
        c.password = "wrong"
        await c.signIn()?.value
        XCTAssertEqual(c.error, "INVALID_CREDENTIALS")
        XCTAssertEqual(c.errorText, "Wrong e-mail or password.")
        XCTAssertTrue(signedIn().isEmpty)
        XCTAssertFalse(c.busy)

        answers["/v1/password/sign-in"] = { _ in .json(418, ["code": "SOMETHING_NEW", "message": "hint for developers"]) }
        await c.signIn()?.value
        XCTAssertEqual(c.errorText, "Something went wrong. Try again.", "an unknown code: the general message")
    }


    // MARK: - Rule 3: sign-up

    func testSignUpThatSignsInAtOnceUsesRiviumsConfirmPage() async {
        answers["/v1/password/sign-up"] = { _ in .json(200, ["userId": "u1", "verificationSent": false, "session": sessionBody(access: "a", refresh: "r", user: "u1")]) }
        let (c, signedIn) = await screen(["password"])
        c.go(.signUp)
        c.email = "new@example.com"
        c.password = "a-good-password"
        await c.signUp()?.value
        XCTAssertEqual(bodies("/v1/password/sign-up").first?["redirectUrl"] as? String, "https://auth.example.test/pages/verify")
        XCTAssertEqual(signedIn().map(\.userId), ["u1"])
        XCTAssertEqual(c.password, "")
    }

    func testSignUpThatNeedsAConfirmedEmailShowsCheckYourEmail() async {
        answers["/v1/password/sign-up"] = { _ in .json(200, ["userId": "u9", "verificationSent": true, "session": NSNull()]) }
        let (c, signedIn) = await screen(["password"], en { $0.verifyRedirectURL = "myapp://verify" })
        c.go(.signUp)
        c.email = "new@example.com"
        c.password = "a-good-password"
        await c.signUp()?.value
        XCTAssertEqual(bodies("/v1/password/sign-up").first?["redirectUrl"] as? String, "myapp://verify")
        XCTAssertEqual(c.screen, .sent)
        XCTAssertEqual(c.sent, .verify)
        XCTAssertTrue(signedIn().isEmpty)
        XCTAssertEqual(c.password, "", "the password is not kept")
    }

    func testSignUpThatNeedsAConfirmedEmailButSentNoneSaysSo() async {
        answers["/v1/password/sign-up"] = { _ in .json(200, ["userId": "u9", "verificationSent": false, "session": NSNull()]) }
        let (c, signedIn) = await screen(["password"])
        c.go(.signUp)
        c.email = "new@example.com"
        c.password = "a-good-password"
        await c.signUp()?.value
        XCTAssertEqual(c.screen, .home)
        XCTAssertEqual(c.error, "VERIFY_NOT_SENT")
        XCTAssertTrue(c.errorText?.contains("could not be sent") == true)
        XCTAssertTrue(signedIn().isEmpty)
        XCTAssertEqual(c.password, "", "the password is not kept")
    }

    // MARK: - Rule 4: forgot password

    func testForgotPasswordWithoutTheAppsURLLetsTheServerPickRiviumsPage() async {
        answers["/v1/password/forgot"] = { _ in .empty(202) }
        let (c, _) = await screen(["password"])
        c.go(.forgot)
        c.email = "ana@example.com"
        await c.sendReset()?.value
        XCTAssertEqual(bodies("/v1/password/forgot").first as? [String: String], ["email": "ana@example.com"], "no redirectUrl at all")
        XCTAssertEqual(c.screen, .sent)
        XCTAssertEqual(c.sent, .reset)
    }

    func testForgotPasswordWithTheAppsURL() async {
        answers["/v1/password/forgot"] = { _ in .empty(202) }
        let (c, _) = await screen(["password"], en { $0.resetRedirectURL = "https://myapp.example/reset" })
        c.go(.forgot)
        c.email = "ana@example.com"
        await c.sendReset()?.value
        XCTAssertEqual(bodies("/v1/password/forgot").first?["redirectUrl"] as? String, "https://myapp.example/reset")
    }

    // MARK: - Magic link

    func testMagicLinkUsesTheAppsURL() async {
        answers["/v1/magic-link/send"] = { _ in .empty(202) }
        let (c, _) = await screen(["magicLink"], en { $0.magicLinkRedirectURL = "https://app.example.com/auth" })
        XCTAssertTrue(c.showMagicLink)
        c.go(.magicLink)
        c.email = "ana@example.com"
        await c.sendMagicLink()?.value
        XCTAssertEqual(bodies("/v1/magic-link/send").first as? [String: String], ["email": "ana@example.com", "redirectUrl": "https://app.example.com/auth"])
        XCTAssertEqual(c.sent, .magicLink)
        XCTAssertEqual(c.screen, .sent)
    }

    // MARK: - Rule 5: Telegram

    func testTelegramOpenTheBotFirstThenTheCode() async {
        bot = "tikashop_bot"
        var sent = false
        answers["/v1/telegram/code"] = { _ in
            sent ? .json(200, ["sent": true, "expiresIn": 300]) : .json(200, ["sent": false, "botUrl": "https://t.me/tikashop_bot", "expiresIn": 0])
        }
        answers["/v1/telegram/verify"] = { r in
            (r.body["code"] as? String) == "123456" ? self.session("u1") : .json(400, ["code": "TOKEN_INVALID", "message": "hint"])
        }
        var opened: [URL] = []
        let (c, signedIn) = await screen(["telegram"], en { $0.openURL = { opened.append($0) } })
        c.go(.telegramPhone)
        c.phone = "+98 (912) 345-6789"
        await c.sendTelegramCode()?.value
        XCTAssertEqual(bodies("/v1/telegram/code").first as? [String: String], ["phone": "+989123456789"])
        XCTAssertEqual(c.screen, .telegramPhone)
        XCTAssertEqual(c.safeBotURL?.absoluteString, "https://t.me/tikashop_bot")
        await c.openBot()?.value
        XCTAssertEqual(opened.map(\.absoluteString), ["https://t.me/tikashop_bot"])

        sent = true
        await c.sendTelegramCode()?.value
        XCTAssertEqual(c.screen, .telegramCode)
        XCTAssertNil(c.botURL)
        c.code = "000000"
        await c.verifyTelegramCode()?.value
        XCTAssertEqual(c.errorText, "This code is wrong or has expired.")
        c.code = "123456"
        await c.verifyTelegramCode()?.value
        XCTAssertEqual(signedIn().map(\.userId), ["u1"])
        XCTAssertEqual(bodies("/v1/telegram/verify").last as? [String: String], ["phone": "+989123456789", "code": "123456"])
    }

    func testABotLinkThatIsNotHttpsTmeIsNeverShownOrOpened() async {
        var opened: [URL] = []
        for link in ["javascript:alert(1)", "http://t.me/tikashop_bot", "https://t.me.evil.example/x", "https://evil.example/t.me"] {
            answers["/v1/telegram/code"] = { _ in .json(200, ["sent": false, "botUrl": link, "expiresIn": 0]) }
            let (c, _) = await screen(["telegram"], en { $0.openURL = { opened.append($0) } })
            c.go(.telegramPhone)
            c.phone = "+989123456789"
            await c.sendTelegramCode()?.value
            XCTAssertNil(c.safeBotURL, link)
            XCTAssertNil(c.openBot(), link)
        }
        XCTAssertTrue(opened.isEmpty)
    }

    func testTelegramWithoutAPhoneSendsNothing() async {
        let (c, _) = await screen(["telegram"])
        c.go(.telegramPhone)
        XCTAssertNil(c.sendTelegramCode())
        XCTAssertEqual(c.errorText, "Check what you entered.")
        XCTAssertTrue(StubURLProtocol.requests(to: "/v1/telegram/code").isEmpty)
    }

    // MARK: - Rule 6: Google and Apple

    func testGoogleTheAppGetsTheHashedNonceRiviumTheRawOne() async {
        answers["/v1/google"] = { _ in self.session("u1") }
        var hashed: [String] = []
        let (c, signedIn) = await screen(["google"], en { $0.google = { hashed.append($0); return "google-id-token" } })
        await c.continueWithGoogle()?.value
        await c.continueWithGoogle()?.value
        let sent = bodies("/v1/google")
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(sent[0]["idToken"] as? String, "google-id-token")
        XCTAssertEqual(sent.map { RiviumNonce.sha256($0["nonce"] as! String) }, hashed)
        XCTAssertNotEqual(hashed[0], hashed[1], "a fresh nonce for each try")
        XCTAssertNotEqual(sent[0]["nonce"] as? String, hashed[0], "Rivium gets the raw nonce, not the hash")
        XCTAssertEqual(signedIn().map(\.userId), ["u1", "u1"])
    }

    func testGoogleCancelledSendsNothingAndShowsNoError() async {
        let (c, signedIn) = await screen(["google"], en { $0.google = { _ in nil } })
        await c.continueWithGoogle()?.value
        XCTAssertTrue(StubURLProtocol.requests(to: "/v1/google").isEmpty)
        XCTAssertNil(c.error)
        XCTAssertTrue(signedIn().isEmpty)
        XCTAssertFalse(c.busy)

        let (thrown, _) = await screen(["google"], en { $0.google = { _ in throw RiviumAuthError(code: .canceled, message: "closed") } })
        await thrown.continueWithGoogle()?.value
        XCTAssertNil(thrown.error, "a cancel thrown by the app is no error either")
    }

    func testAppleTheAppGetsTheHashedNonceRiviumTheRawOneAndTheCode() async {
        answers["/v1/apple"] = { _ in self.session("u2") }
        var hashed = ""
        let (c, signedIn) = await screen(["apple"], en {
            $0.apple = { hashed = $0; return RiviumAppleCredential(idToken: "apple-id", authorizationCode: "code-1", fullName: "Ana") }
        })
        await c.continueWithApple()?.value
        let body = bodies("/v1/apple").first
        XCTAssertEqual(body?["idToken"] as? String, "apple-id")
        XCTAssertEqual(body?["authorizationCode"] as? String, "code-1")
        XCTAssertEqual(body?["name"] as? String, "Ana")
        XCTAssertEqual(RiviumNonce.sha256(body?["nonce"] as? String ?? ""), hashed)
        XCTAssertEqual(signedIn().map(\.userId), ["u2"])

        let (cancel, _) = await screen(["apple"], en { $0.apple = { _ in nil } })
        await cancel.continueWithApple()?.value
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/apple").count, 1, "cancelled: nothing sent")
        XCTAssertNil(cancel.error)
    }

    // MARK: - Rule 7: one action at a time, no closing while busy

    func testBusyBlocksASecondActionAndClosing() async {
        answers["/v1/password/sign-in"] = { _ in .json(200, sessionBody(access: "a", refresh: "r", user: "u1"), delay: 0.3) }
        answers["/v1/anonymous"] = { _ in self.session("guest") }
        let (c, signedIn) = await screen(["password", "anonymous"], en { $0.allowGuest = true })
        c.email = "ana@example.com"
        c.password = "a-good-password"
        XCTAssertTrue(c.canClose)
        let first = c.signIn()
        XCTAssertNotNil(first)
        XCTAssertTrue(c.busy, "busy before anything is awaited")
        XCTAssertFalse(c.canClose, "no closing while a sign-in runs")
        XCTAssertNil(c.signIn(), "a second tap starts nothing")
        XCTAssertNil(c.continueAsGuest())
        c.go(.forgot)
        XCTAssertEqual(c.screen, .home, "no navigation while busy")
        await first?.value
        XCTAssertFalse(c.busy)
        XCTAssertTrue(c.canClose)
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/password/sign-in").count, 1)
        XCTAssertTrue(StubURLProtocol.requests(to: "/v1/anonymous").isEmpty)
        XCTAssertEqual(signedIn().map(\.userId), ["u1"])
    }

    func testASignInThatEndsAfterCloseIsNotReported() async {
        answers["/v1/anonymous"] = { _ in .json(200, sessionBody(access: "a", refresh: "r", user: "g"), delay: 0.2) }
        let (c, signedIn) = await screen(["anonymous"], en { $0.allowGuest = true })
        let task = c.continueAsGuest()
        c.close()
        await task?.value
        XCTAssertTrue(signedIn().isEmpty)
    }

    func testGuest() async {
        answers["/v1/anonymous"] = { _ in self.session("guest-1") }
        let (c, signedIn) = await screen(["anonymous"], en { $0.allowGuest = true })
        XCTAssertEqual(c.screen, .home)
        await c.continueAsGuest()?.value
        XCTAssertEqual(signedIn().map(\.userId), ["guest-1"])
    }

    // MARK: - Rule 9: e-mail language

    func testTheEmailsFollowTheOpenScreenGivenBackOnCloseNeverTheAppsOwnChoice() async {
        let auth = client()
        let (c, _) = await screen(["password"], RiviumSignInOptions(languageCode: "en"), auth: auth)
        XCTAssertEqual(auth.languageCode, "en")
        c.close()
        XCTAssertNil(auth.languageCode, "given back")

        auth.languageCode = "en-US"
        let (d, _) = await screen(["password"], RiviumSignInOptions(languageCode: "en"), auth: auth)
        XCTAssertEqual(d.strings.languageCode, "en")
        XCTAssertEqual(auth.languageCode, "en-US", "the app's own choice stays")
        d.close()
        XCTAssertEqual(auth.languageCode, "en-US")
    }

    func testTwoOverlappingScreensKeepTheLanguageUntilTheLastCloses() async {
        let auth = client()
        let (a, _) = await screen(["password"], RiviumSignInOptions(languageCode: "en"), auth: auth)
        let (b, _) = await screen(["password"], RiviumSignInOptions(languageCode: "en"), auth: auth) // opens before a closes
        a.close()
        XCTAssertEqual(auth.languageCode, "en", "b is still open")
        b.close()
        XCTAssertNil(auth.languageCode)
        b.close()
        XCTAssertNil(auth.languageCode, "closing twice changes nothing")
    }

    func testTheAppChangingTheLanguageWhileOpenIsKept() async {
        let auth = client()
        let (c, _) = await screen(["password"], RiviumSignInOptions(languageCode: "en"), auth: auth)
        auth.languageCode = "de"
        c.close()
        XCTAssertEqual(auth.languageCode, "de")
    }

    func testTheAppLanguageDecidesWhenNoLanguageCodeIsGiven() {
        let c = RiviumSignInController(auth: client())
        XCTAssertEqual(c.strings, RiviumSignInStrings.of(RiviumSignInController.appLanguage()))
    }

    func testClosingForgetsThePassword() async {
        let (c, _) = await screen(["password"])
        c.password = "secret-pass"
        c.close()
        XCTAssertEqual(c.password, "")
    }

    // MARK: - 0.5.0: "Send again" for an unconfirmed e-mail

    private func unconfirmed(_ options: RiviumSignInOptions = RiviumSignInOptions(languageCode: "en")) async -> RiviumSignInController {
        answers["/v1/password/sign-in"] = { _ in .json(403, ["code": "EMAIL_NOT_VERIFIED", "message": "Confirm the e-mail first"]) }
        let (c, _) = await screen(["password"], options)
        c.email = " ana@example.com "
        c.password = "a-good-password"
        XCTAssertFalse(c.canResend, "no Send again before sign-in failed")
        await c.signIn()?.value
        return c
    }

    func testEmailNotVerifiedOffersSendAgain() async {
        let c = await unconfirmed()
        XCTAssertEqual(c.error, "EMAIL_NOT_VERIFIED")
        XCTAssertEqual(c.errorText, "Confirm your e-mail first. Check your inbox.")
        XCTAssertTrue(c.canResend)
        XCTAssertEqual(c.strings["resend"], "Send again")

        answers["/v1/password/sign-in"] = { _ in .json(401, ["code": "INVALID_CREDENTIALS", "message": "no"]) }
        await c.signIn()?.value
        XCTAssertFalse(c.canResend, "only for EMAIL_NOT_VERIFIED")
    }

    func testSendAgainCallsTheEndpointWithTheTypedEmailAndPasswordThenSaysANewLinkWasSent() async {
        let c = await unconfirmed(en { $0.continueURL = "https://myapp.example/done" })
        var resent: [String: Any] = [:]
        answers["/v1/email/resend-verification"] = { r in
            resent = r.body
            return .json(202, ["ok": true], delay: 0.2)
        }
        let task = c.resendVerification()
        XCTAssertNotNil(task)
        XCTAssertTrue(c.busy, "busy while sending")
        XCTAssertNil(c.resendVerification(), "one send at a time")
        await task?.value
        XCTAssertFalse(c.busy)
        XCTAssertEqual(resent as? [String: String], [
            "email": "ana@example.com", "password": "a-good-password",
            "redirectUrl": "https://auth.example.test/pages/verify", "continueUrl": "https://myapp.example/done",
        ])
        XCTAssertEqual(StubURLProtocol.requests(to: "/v1/email/resend-verification").count, 1)
        XCTAssertNil(StubURLProtocol.requests(to: "/v1/email/resend-verification")[0].headers["Authorization"])
        XCTAssertEqual(c.screen, .sent)
        XCTAssertEqual(c.sent, .resend)
        XCTAssertEqual(c.password, "", "the password is not kept")
        XCTAssertNil(c.auth.currentUserId, "nobody is signed in")
        XCTAssertEqual(c.strings["resendSent"].replacingOccurrences(of: "{email}", with: "ana@example.com"), "We sent a new link to ana@example.com.")
    }

    func testSendAgainUsesTheAppsConfirmURLAndNoContinueURLWhenNotSet() async {
        let c = await unconfirmed(en { $0.verifyRedirectURL = "myapp://verify" })
        answers["/v1/email/resend-verification"] = { _ in .json(202, ["ok": true]) }
        await c.resendVerification()?.value
        XCTAssertEqual(bodies("/v1/email/resend-verification").first as? [String: String], [
            "email": "ana@example.com", "password": "a-good-password", "redirectUrl": "myapp://verify",
        ])
    }

    func testSendAgainErrorsAreShownLikeOtherErrors() async {
        let c = await unconfirmed()
        answers["/v1/email/resend-verification"] = { _ in .json(429, ["code": "RATE_LIMITED", "message": "slow"]) }
        await c.resendVerification()?.value
        XCTAssertEqual(c.screen, .home)
        XCTAssertEqual(c.error, "RATE_LIMITED")
        XCTAssertEqual(c.errorText, "Too many tries. Wait a little and try again.")
        XCTAssertFalse(c.busy)
        XCTAssertNil(c.auth.currentUserId)

        let d = await unconfirmed()
        answers["/v1/email/resend-verification"] = { _ in .json(401, ["code": "INVALID_CREDENTIALS", "message": "no"]) }
        await d.resendVerification()?.value
        XCTAssertEqual(d.errorText, "Wrong e-mail or password.")
    }

    func testSendAgainNeedsTheTypedPasswordAndTheErrorFirst() async {
        let (c, _) = await screen(["password"])
        c.email = "ana@example.com"
        c.password = "a-good-password"
        XCTAssertNil(c.resendVerification(), "not offered before sign-in answered EMAIL_NOT_VERIFIED")
        let d = await unconfirmed()
        d.password = ""
        XCTAssertFalse(d.canResend)
        XCTAssertNil(d.resendVerification())
        XCTAssertTrue(StubURLProtocol.requests(to: "/v1/email/resend-verification").isEmpty)
    }

    func testContinueURLGoesToSignUpAndForgotPassword() async {
        answers["/v1/password/sign-up"] = { _ in .json(200, ["userId": "u9", "verificationSent": true, "session": NSNull()]) }
        answers["/v1/password/forgot"] = { _ in .empty(202) }
        let (c, _) = await screen(["password"], en { $0.continueURL = "https://myapp.example/done" })
        c.go(.signUp)
        c.email = "new@example.com"
        c.password = "a-good-password"
        await c.signUp()?.value
        XCTAssertEqual(bodies("/v1/password/sign-up").first?["continueUrl"] as? String, "https://myapp.example/done")
        c.go(.forgot)
        await c.sendReset()?.value
        XCTAssertEqual(bodies("/v1/password/forgot").first as? [String: String], ["email": "new@example.com", "continueUrl": "https://myapp.example/done"])

        let (plain, _) = await screen(["password"])
        plain.go(.signUp)
        plain.email = "new2@example.com"
        plain.password = "a-good-password"
        await plain.signUp()?.value
        XCTAssertNil(bodies("/v1/password/sign-up").last?["continueUrl"], "no continueUrl when not set")
    }

    // MARK: - Texts

    func testTheTexts() {
        XCTAssertEqual(RiviumSignInStrings.keys.count, 56)
        XCTAssertEqual(RiviumSignInStrings.of("de").error("NOPE"), "Something went wrong. Try again.")
        for code in ["de", "de-DE", "", "toString", "EN_us"] as [String] {
            XCTAssertEqual(RiviumSignInStrings.of(code).languageCode, "en", code)
            XCTAssertFalse(RiviumSignInStrings.of(code).isRightToLeft, code)
        }
        XCTAssertEqual(RiviumSignInStrings.of(nil).languageCode, "en")
    }

    // MARK: - SDK additions

    func testBaseURLAndResetWithoutURL() async throws {
        let auth = client()
        XCTAssertEqual(auth.baseURL, base)
        XCTAssertEqual(RiviumAuth().baseURL, RiviumAuth.defaultBaseURL)
        answers["/v1/password/forgot"] = { _ in .empty(202) }
        try await auth.sendPasswordReset(email: "a@example.com")
        try await auth.sendPasswordReset(email: "a@example.com", redirectURL: "https://x.example/reset")
        XCTAssertEqual(bodies("/v1/password/forgot").map { $0["redirectUrl"] as? String }, [nil, "https://x.example/reset"])
        XCTAssertEqual(RiviumSignInController.page(URL(string: "https://a.example/")!, "verify"), "https://a.example/pages/verify")
    }
}

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// The sheet: answers once, cannot be closed while a sign-in runs.
@available(iOS 15.0, *)
@MainActor
final class SignInPresentationTests: XCTestCase {
    func testSheetRefusesToCloseWhileBusyAndAnswersOnce() async {
        StubURLProtocol.reset { r in
            switch r.path {
            case "/v1/methods": return .json(200, ["methods": ["anonymous"]])
            case "/v1/anonymous": return .json(200, sessionBody(access: "a", refresh: "r", user: "g"), delay: 0.2)
            default: return .empty(404)
            }
        }
        let auth = RiviumAuth()
        auth.configure(apiKey: "rv_live_test", baseURL: URL(string: "https://auth.example.test")!, urlSession: StubURLProtocol.session(), storage: MemorySessionStorage(nil))
        var answers: [String?] = []
        let controller = RiviumSignInController(auth: auth, options: RiviumSignInOptions(languageCode: "en", allowGuest: true))
        let p = SignInPresentation(controller: controller) { answers.append($0?.userId) }
        let phone = p.makeHost(tint: nil, regularWidth: false)
        XCTAssertEqual(phone.modalPresentationStyle, .fullScreen)
        let host = p.makeHost(tint: .systemPink, regularWidth: true)
        XCTAssertEqual(host.modalPresentationStyle, .formSheet)
        await controller.load().value

        let task = controller.continueAsGuest()
        let sheet = UIPresentationController(presentedViewController: host, presenting: nil)
        XCTAssertFalse(p.presentationControllerShouldDismiss(sheet), "no swipe-down while busy")
        XCTAssertTrue(host.isModalInPresentation)
        p.dismiss(with: nil)
        XCTAssertTrue(answers.isEmpty, "the close button does nothing while busy")
        await task?.value
        XCTAssertEqual(answers, ["g"])
        XCTAssertFalse(host.isModalInPresentation)
        p.presentationControllerDidDismiss(sheet)
        XCTAssertEqual(answers, ["g"], "answers once")
    }

    func testClosedAnswersNil() {
        var answers: [String?] = []
        let p = SignInPresentation(controller: RiviumSignInController(auth: RiviumAuth(), options: RiviumSignInOptions(languageCode: "en"))) { answers.append($0?.userId) }
        _ = p.makeHost(tint: nil, regularWidth: false)
        p.dismiss(with: nil)
        XCTAssertEqual(answers, [nil])
    }
}
#endif
