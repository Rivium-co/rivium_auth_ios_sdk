import Foundation

/// The result of a sign-in, a sign-up that signed in, or a link.
public struct AuthResult: Equatable {
    public let userId: String
    /// True when this sign-in created the user. Reported for Apple and Google
    /// sign-in; nil for the other methods.
    public let isNewUser: Bool?
}

/// The result of `signUp(email:password:redirectURL:)`.
public struct SignUpResult: Equatable {
    public let userId: String
    /// A verification e-mail was sent.
    public let verificationSent: Bool
    /// The user is signed in now. False when the project requires a verified
    /// e-mail first: the user signs in after following the link.
    public let signedIn: Bool
}

/// The signed-in user, as returned by `me()`.
public struct RiviumUser: Equatable {
    public let id: String
    public let isAnonymous: Bool
    public let emailVerified: Bool
    public let createdAt: Date?
    /// Linked sign-in methods: "apple", "google", "password", ...
    public let providers: [String]
}

/// The sign-in methods the project offers. Show only these buttons.
public struct AuthMethods: Equatable {
    /// "anonymous", "password", "magicLink", "apple", "google", "telegram", ...
    public let methods: [String]
    /// The project's Telegram bot username, when Telegram sign-in is on.
    public let telegramBot: String?

    public func isEnabled(_ method: String) -> Bool { methods.contains(method) }
}

/// The result of `requestTelegramCode(phone:)`.
public struct TelegramCodeResult: Equatable {
    /// The code was sent to the user's Telegram chat.
    public let sent: Bool
    /// When `sent` is false: open this link so the user starts the bot and
    /// shares their phone number; the code then arrives in Telegram.
    public let botURL: URL?
    /// Seconds the code stays valid.
    public let expiresIn: Int
}

// MARK: - Wire types

struct SessionTokens: Decodable, Equatable {
    let accessToken: String
    let expiresIn: Double
    let refreshToken: String
    let userId: String
    let created: Bool?
}

struct SignUpResponse: Decodable {
    let userId: String
    let verificationSent: Bool?
    let session: SessionTokens?
}

struct PublicUserResponse: Decodable {
    let id: String
    let anonymous: Bool
    let emailVerified: Bool
    let createdAt: String?
    let providers: [String]?
}

struct MethodsResponse: Decodable {
    let methods: [String]
    let telegramBot: String?
}

struct TelegramCodeResponse: Decodable {
    let sent: Bool
    let botUrl: String?
    let expiresIn: Int?
}

struct ErrorResponse: Decodable {
    let code: String?
    let message: String?
    let retryAfterSec: Int?
    let fields: [String: String]?
}

extension RiviumUser {
    init(_ r: PublicUserResponse) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(
            id: r.id,
            isAnonymous: r.anonymous,
            emailVerified: r.emailVerified,
            createdAt: r.createdAt.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) },
            providers: r.providers ?? []
        )
    }
}
