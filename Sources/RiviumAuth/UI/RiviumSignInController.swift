import Combine
import Foundation

/// Holds the ready-made sign-in screen's state and runs the SDK calls. `RiviumSignInView` only reads it and calls
/// its methods. Every action returns the `Task` it started (nil when it started none), so you can await it.
@MainActor
public final class RiviumSignInController: ObservableObject {
    /// The sign-in screens.
    public enum Screen: Equatable {
        case loading, home, signUp, forgot, magicLink, telegramPhone, telegramCode, sent, unavailable
    }

    /// Which e-mail the "check your e-mail" screen is about.
    public enum SentKind: Equatable {
        case reset, magicLink, verify
    }

    public let auth: RiviumAuth
    public let options: RiviumSignInOptions
    public let strings: RiviumSignInStrings

    /// Called once a user is signed in.
    var onSignedIn: ((AuthResult) -> Void)?

    @Published public private(set) var screen: Screen = .loading
    @Published public private(set) var methods = AuthMethods(methods: [], telegramBot: nil)
    /// An action runs: every button is off and the screen cannot be closed.
    @Published public private(set) var busy = false
    /// The error code of the last failed action, or nil.
    @Published public private(set) var error: String?
    @Published public private(set) var sent: SentKind?
    /// The Telegram bot link when the user has to open the bot first.
    @Published public private(set) var botURL: URL?

    @Published public var email = ""
    @Published public var password = ""
    @Published public var phone = ""
    @Published public var code = ""

    /// Field errors, shown under the field.
    @Published public private(set) var emailError: String?
    @Published public private(set) var passwordError: String?

    /// The screen set `RiviumAuth.languageCode` (it was unset) and gives it back on close.
    private var languageHeld = false
    private var closed = false
    private var loaded = false

    /// - Parameters:
    ///   - auth: The client to sign in with.
    ///   - options: What the screen offers and how it looks.
    ///   - onSignedIn: Called once a user is signed in.
    public init(auth: RiviumAuth = .shared, options: RiviumSignInOptions = RiviumSignInOptions(), onSignedIn: ((AuthResult) -> Void)? = nil) {
        self.auth = auth
        self.options = options
        self.strings = RiviumSignInStrings.of(options.languageCode ?? Self.appLanguage())
        self.onSignedIn = onSignedIn
    }

    /// The app's language: the first of its localizations the user prefers.
    static func appLanguage() -> String? {
        Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first
    }

    // MARK: - What the screen shows

    public var showPassword: Bool { methods.isEnabled("password") }
    public var showMagicLink: Bool { methods.isEnabled("magicLink") && !(options.magicLinkRedirectURL ?? "").isEmpty }
    public var showTelegram: Bool { methods.isEnabled("telegram") }
    public var showGoogle: Bool { methods.isEnabled("google") && options.google != nil }
    public var showApple: Bool { methods.isEnabled("apple") && options.apple != nil }
    public var showGuest: Bool { methods.isEnabled("anonymous") && options.allowGuest }

    /// Buttons under the e-mail form (or alone when there is no form).
    public var hasOtherMethods: Bool { showMagicLink || showTelegram || showGoogle || showApple || showGuest }

    /// The message for `error`, in the screen's language.
    public var errorText: String? { error.map(strings.error) }

    /// The screen may be closed: no action runs.
    public var canClose: Bool { !busy }

    public var title: String {
        let name = (options.appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? strings["title"] : strings["titleTo"].replacingOccurrences(of: "{app}", with: name)
    }

    /// The bot link, only when it is an https Telegram address.
    public var safeBotURL: URL? {
        guard let url = botURL, url.scheme == "https", url.host == "t.me" else { return nil }
        return url
    }

    // MARK: - Opening and closing

    /// Loads the project's methods and opens the first screen.
    @discardableResult
    public func load() -> Task<Void, Never> {
        closed = false
        loaded = true
        holdLanguage()
        screen = .loading
        return Task {
            do {
                methods = try await auth.getMethods()
                error = nil
                screen = showPassword || hasOtherMethods ? .home : .unavailable
            } catch {
                self.error = Self.code(of: error)
                screen = .unavailable
            }
        }
    }

    /// The view appeared: loads once; after a close, takes the e-mail language again.
    func appear() {
        if loaded {
            closed = false
            holdLanguage()
        } else {
            load()
        }
    }

    /// The screen closed: forgets the password and gives the e-mail language back. A sign-in that ends later is
    /// not reported.
    public func close() {
        closed = true
        password = ""
        releaseLanguage()
    }

    /// While the screen is open the e-mails follow its language, unless the app chose a language itself.
    private func holdLanguage() {
        guard !languageHeld else { return }
        languageHeld = LanguageHolds.hold(auth, strings.languageCode)
    }

    private func releaseLanguage() {
        guard languageHeld else { return }
        languageHeld = false
        LanguageHolds.release(auth)
    }

    deinit {
        // A screen dropped without close() (an embedded RiviumSignInView that went away) gives the language back too.
        guard languageHeld else { return }
        let auth = auth
        Task { @MainActor in LanguageHolds.release(auth) }
    }

    // MARK: - Navigation

    /// Opens `screen`, clearing the last error.
    public func go(_ screen: Screen) {
        guard !busy else { return }
        error = nil
        emailError = nil
        passwordError = nil
        if screen == .telegramPhone {
            code = ""
            botURL = nil
        }
        self.screen = screen
    }

    public func back() { go(.home) }

    // MARK: - Actions

    @discardableResult
    public func signIn() -> Task<Void, Never>? {
        guard !busy, checkEmail(needPassword: true) else { return nil }
        let email = trimmedEmail, password = password
        return run { [auth] in self.done(try await auth.signIn(email: email, password: password)) }
    }

    @discardableResult
    public func signUp() -> Task<Void, Never>? {
        guard !busy, checkEmail(needPassword: true) else { return nil }
        let email = trimmedEmail, password = password
        let redirect = options.verifyRedirectURL ?? Self.page(auth.baseURL, "verify")
        return run { [auth] in
            let r = try await auth.signUp(email: email, password: password, redirectURL: redirect)
            if r.signedIn { return self.done(AuthResult(userId: r.userId, isNewUser: nil)) }
            self.password = ""
            if !r.verificationSent {
                // The account exists but must be confirmed, and no e-mail went out.
                self.error = "VERIFY_NOT_SENT"
                self.screen = .home
                return
            }
            self.sent = .verify
            self.screen = .sent
        }
    }

    @discardableResult
    public func sendReset() -> Task<Void, Never>? {
        guard !busy, checkEmail() else { return nil }
        let email = trimmedEmail
        // No URL of the app's own: the server uses Rivium's reset page.
        let redirect = options.resetRedirectURL
        return run { [auth] in
            try await auth.sendPasswordReset(email: email, redirectURL: redirect)
            self.sent = .reset
            self.screen = .sent
        }
    }

    @discardableResult
    public func sendMagicLink() -> Task<Void, Never>? {
        guard !busy, let redirect = options.magicLinkRedirectURL, !redirect.isEmpty, checkEmail() else { return nil }
        let email = trimmedEmail
        return run { [auth] in
            try await auth.sendMagicLink(email: email, redirectURL: redirect)
            self.sent = .magicLink
            self.screen = .sent
        }
    }

    @discardableResult
    public func sendTelegramCode() -> Task<Void, Never>? {
        guard !busy else { return nil }
        guard !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = RiviumAuthError.Code.invalidInput.rawValue
            return nil
        }
        let phone = normalizedPhone
        return run { [auth] in
            let r = try await auth.requestTelegramCode(phone: phone)
            self.botURL = r.sent ? nil : r.botURL
            if r.sent {
                self.code = ""
                self.screen = .telegramCode
            }
        }
    }

    @discardableResult
    public func verifyTelegramCode() -> Task<Void, Never>? {
        guard !busy else { return nil }
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            error = RiviumAuthError.Code.invalidInput.rawValue
            return nil
        }
        let phone = normalizedPhone
        return run { [auth] in self.done(try await auth.verifyTelegramCode(phone: phone, code: code)) }
    }

    @discardableResult
    public func continueAsGuest() -> Task<Void, Never>? {
        guard !busy, showGuest else { return nil }
        return run { [auth] in self.done(try await auth.signInAnonymously()) }
    }

    @discardableResult
    public func continueWithGoogle() -> Task<Void, Never>? {
        guard !busy, let google = options.google else { return nil }
        return run { [auth] in
            // A fresh nonce for each try: the app's Google sign-in gets the hash, Rivium the raw value.
            let raw = RiviumNonce.generate()
            guard let idToken = try await google(RiviumNonce.sha256(raw)) else { return } // cancelled
            self.done(try await auth.signInWithGoogle(idToken: idToken, rawNonce: raw))
        }
    }

    @discardableResult
    public func continueWithApple() -> Task<Void, Never>? {
        guard !busy, let apple = options.apple else { return nil }
        return run { [auth] in
            let raw = RiviumNonce.generate()
            guard let c = try await apple(RiviumNonce.sha256(raw)) else { return } // cancelled
            self.done(try await auth.signInWithApple(
                idToken: c.idToken, rawNonce: raw, authorizationCode: c.authorizationCode, fullName: c.fullName))
        }
    }

    /// Opens the Telegram bot through the app's `openURL`, only when the link is safe.
    @discardableResult
    public func openBot() -> Task<Void, Never>? {
        guard let url = safeBotURL, let open = options.openURL else { return nil }
        return Task { await open(url) }
    }

    // MARK: - Internals

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The phone number without spaces, dashes and brackets.
    var normalizedPhone: String {
        phone.replacingOccurrences(of: "[\\s\\-()]", with: "", options: .regularExpression)
    }

    static func page(_ base: URL, _ name: String) -> String {
        var s = base.absoluteString
        while s.hasSuffix("/") { s.removeLast() }
        return "\(s)/pages/\(name)"
    }

    private func checkEmail(needPassword: Bool = false) -> Bool {
        let e = trimmedEmail
        emailError = e.isEmpty
            ? strings["required"]
            : (e.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) == nil ? strings["badEmail"] : nil)
        passwordError = needPassword && password.isEmpty ? strings["required"] : nil
        error = nil
        return emailError == nil && passwordError == nil
    }

    private func done(_ result: AuthResult) {
        password = ""
        guard !closed else { return }
        onSignedIn?(result)
    }

    /// Runs one action at a time. `busy` is set before anything is awaited, so a second tap or a close in the
    /// meantime is refused.
    private func run(_ action: @escaping @MainActor () async throws -> Void) -> Task<Void, Never> {
        error = nil
        busy = true
        return Task {
            do {
                try await action()
            } catch {
                let code = Self.code(of: error)
                // The app's Google or Apple sign-in was closed: no error to show.
                if code != RiviumAuthError.Code.canceled.rawValue { self.error = code }
            }
            self.busy = false
        }
    }

    static func code(of error: Error) -> String {
        (error as? RiviumAuthError)?.code.rawValue ?? "UNKNOWN"
    }
}

/// The language the open sign-in screens set on each client, and how many are open: given back (unset) when the
/// last one closes and the value is still theirs. A language the app set itself is never replaced.
@MainActor
enum LanguageHolds {
    private static var all: [ObjectIdentifier: (count: Int, value: String)] = [:]

    /// Sets `language` on `auth` when it is unset or holds the open screens' value. True when it did.
    static func hold(_ auth: RiviumAuth, _ language: String) -> Bool {
        let key = ObjectIdentifier(auth)
        let current = auth.languageCode
        if let hold = all[key] {
            guard current == hold.value else { return false }
            all[key] = (hold.count + 1, language)
        } else {
            guard current == nil else { return false }
            all[key] = (1, language)
        }
        auth.languageCode = language
        return true
    }

    static func release(_ auth: RiviumAuth) {
        let key = ObjectIdentifier(auth)
        guard let hold = all[key] else { return }
        if hold.count > 1 {
            all[key] = (hold.count - 1, hold.value)
            return
        }
        all[key] = nil
        if auth.languageCode == hold.value { auth.languageCode = nil }
    }
}
