import Foundation

/// An error from Rivium Auth.
///
/// Branch on `code`, never on `message`: the message is an English hint for
/// developers, the code is stable.
///
/// ```swift
/// do {
///     try await RiviumAuth.shared.linkGoogle(idToken: idToken, rawNonce: nonce)
/// } catch let error as RiviumAuthError where error.code == .providerAlreadyLinked {
///     // This Google account already belongs to another user.
/// }
/// ```
public struct RiviumAuthError: Error, LocalizedError, CustomStringConvertible {
    /// A stable error code. Server codes keep their server spelling.
    public struct Code: RawRepresentable, Hashable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public var description: String { rawValue }

        // Server codes
        public static let invalidInput = Code(rawValue: "INVALID_INPUT")
        public static let invalidApiKey = Code(rawValue: "INVALID_API_KEY")
        public static let methodDisabled = Code(rawValue: "METHOD_DISABLED")
        public static let invalidCredentials = Code(rawValue: "INVALID_CREDENTIALS")
        public static let emailTaken = Code(rawValue: "EMAIL_TAKEN")
        public static let emailNotVerified = Code(rawValue: "EMAIL_NOT_VERIFIED")
        public static let weakPassword = Code(rawValue: "WEAK_PASSWORD")
        public static let invalidIdToken = Code(rawValue: "INVALID_ID_TOKEN")
        public static let nonceReused = Code(rawValue: "NONCE_REUSED")
        public static let providerAlreadyLinked = Code(rawValue: "PROVIDER_ALREADY_LINKED")
        public static let tokenInvalid = Code(rawValue: "TOKEN_INVALID")
        public static let sessionExpired = Code(rawValue: "SESSION_EXPIRED")
        public static let sessionRevoked = Code(rawValue: "SESSION_REVOKED")
        public static let userDisabled = Code(rawValue: "USER_DISABLED")
        public static let unauthenticated = Code(rawValue: "UNAUTHENTICATED")
        public static let rateLimited = Code(rawValue: "RATE_LIMITED")
        public static let limitReached = Code(rawValue: "LIMIT_REACHED")
        public static let productDisabled = Code(rawValue: "PRODUCT_DISABLED")
        public static let mauLimit = Code(rawValue: "MAU_LIMIT")
        public static let notConfigured = Code(rawValue: "NOT_CONFIGURED")
        public static let `internal` = Code(rawValue: "INTERNAL")

        // Client codes
        /// `RiviumAuth.shared.configure(apiKey:)` was not called.
        public static let sdkNotConfigured = Code(rawValue: "SDK_NOT_CONFIGURED")
        /// The call needs a signed-in user and there is none.
        public static let notSignedIn = Code(rawValue: "NOT_SIGNED_IN")
        /// No connection, a timeout, or the server could not be reached.
        public static let network = Code(rawValue: "NETWORK_ERROR")
        /// The server answered something the SDK could not read.
        public static let invalidResponse = Code(rawValue: "INVALID_RESPONSE")
        /// The user closed the native sign-in sheet.
        public static let canceled = Code(rawValue: "CANCELED")
    }

    public let code: Code
    public let message: String
    /// The HTTP status, or 0 when the request never got an answer.
    public let httpStatus: Int
    /// For `.rateLimited`: seconds to wait before trying again.
    public let retryAfterSec: Int?
    /// For `.invalidInput`: which fields were refused and why.
    public let fields: [String: String]?
    /// The underlying error, for `.network` and native sign-in failures.
    public let underlying: Error?

    public init(
        code: Code,
        message: String,
        httpStatus: Int = 0,
        retryAfterSec: Int? = nil,
        fields: [String: String]? = nil,
        underlying: Error? = nil
    ) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
        self.retryAfterSec = retryAfterSec
        self.fields = fields
        self.underlying = underlying
    }

    public var errorDescription: String? { "\(code.rawValue): \(message)" }
    public var description: String { "RiviumAuthError(\(code.rawValue), \(httpStatus)): \(message)" }

    /// The session cannot be refreshed any more: the user has to sign in again.
    var endsSession: Bool {
        code == .sessionRevoked || code == .sessionExpired || code == .tokenInvalid || code == .userDisabled
    }

    static let notSignedIn = RiviumAuthError(code: .notSignedIn, message: "No user is signed in")
    static let sdkNotConfigured = RiviumAuthError(
        code: .sdkNotConfigured,
        message: "Call RiviumAuth.shared.configure(apiKey:) first"
    )
}
