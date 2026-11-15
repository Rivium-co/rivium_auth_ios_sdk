import SwiftUI

/// The ready-made sign-in form, like FirebaseUI, to put on any screen of your app. It shows only the methods turned
/// on in the Console and calls `onSignedIn` once a user is signed in. `RiviumSignIn.present(from:)` opens it as a
/// sheet and answers the user.
///
/// ```swift
/// RiviumSignInView(options: RiviumSignInOptions(appName: "My Shop")) { result in
///     print(result.userId)
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct RiviumSignInView: View {
    @StateObject private var controller: RiviumSignInController
    private let onClose: (() -> Void)?

    /// - Parameters:
    ///   - auth: The client to sign in with.
    ///   - options: What the screen offers and how it looks.
    ///   - onSignedIn: Called once a user is signed in.
    ///   - onClose: Shows a close button (off while a sign-in runs).
    public init(
        auth: RiviumAuth = .shared,
        options: RiviumSignInOptions = RiviumSignInOptions(),
        onSignedIn: @escaping (AuthResult) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        _controller = StateObject(wrappedValue: RiviumSignInController(auth: auth, options: options, onSignedIn: onSignedIn))
        self.onClose = onClose
    }

    public var body: some View {
        RiviumSignInContent(c: controller, onClose: onClose)
    }
}

/// The screens of one controller. The presenting code owns the controller.
@available(iOS 15.0, macOS 12.0, *)
struct RiviumSignInContent: View {
    @ObservedObject var c: RiviumSignInController
    let onClose: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                screen
                    .frame(maxWidth: 400)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, onClose == nil ? 24 : 48)
            .padding(.bottom, 24)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose = onClose {
                Button {
                    if c.canClose { onClose() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(!c.canClose)
                .accessibilityLabel(Text(c.strings["close"]))
                .accessibilityIdentifier("rivium-close")
                .padding(4)
            }
        }
        // No closing while a sign-in runs: it could land after the screen answered nil.
        .interactiveDismissDisabled(c.busy)
        .environment(\.layoutDirection, c.strings.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.locale, Locale(identifier: c.strings.languageCode))
        .onAppear { c.appear() }
    }

    @ViewBuilder private var screen: some View {
        let s = c.strings
        switch c.screen {
        case .loading:
            ProgressView().padding(48)
        case .home:
            HomeScreen(c: c)
        case .signUp:
            SignUpScreen(c: c)
        case .forgot:
            EmailOnlyScreen(c: c, title: s["forgotTitle"], action: s["sendReset"], id: "forgot") { c.sendReset() }
        case .magicLink:
            EmailOnlyScreen(c: c, title: s["magicTitle"], action: s["sendLink"], id: "magic-link") { c.sendMagicLink() }
        case .telegramPhone, .telegramCode:
            TelegramScreen(c: c)
        case .sent, .unavailable:
            MessageScreen(c: c)
        }
    }
}

// MARK: - Screens

@available(iOS 15.0, macOS 12.0, *)
private struct HomeScreen: View {
    @ObservedObject var c: RiviumSignInController

    var body: some View {
        let s = c.strings
        VStack(spacing: 12) {
            Header(c: c, title: c.title)
            ErrorBanner(text: c.errorText)
            if c.canResend {
                Button(s["resend"]) { c.resendVerification() }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("rivium-resend")
            }
            if c.showPassword {
                Field(label: s["email"], text: $c.email, error: c.emailError, kind: .email, id: "rivium-email", submit: .next)
                Field(label: s["password"], text: $c.password, error: c.passwordError, kind: .password, id: "rivium-password", submit: .done) {
                    c.signIn()
                }
                HStack {
                    Spacer()
                    Button(s["forgot"]) { c.go(.forgot) }
                        .font(.subheadline)
                        .accessibilityIdentifier("rivium-forgot")
                }
                PrimaryButton(label: s["signIn"], busy: c.busy, id: "rivium-sign-in") { c.signIn() }
                Button(s["noAccount"]) { c.go(.signUp) }
                    .font(.subheadline)
                    .accessibilityIdentifier("rivium-to-sign-up")
            }
            if c.showPassword && c.hasOtherMethods {
                HStack(spacing: 12) {
                    Rule()
                    Text(s["or"]).font(.subheadline).foregroundColor(.secondary)
                    Rule()
                }
                .padding(.vertical, 4)
            }
            if c.hasOtherMethods { OtherMethods(c: c) }
        }
        .disabled(c.busy)
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct SignUpScreen: View {
    @ObservedObject var c: RiviumSignInController

    var body: some View {
        let s = c.strings
        VStack(spacing: 12) {
            Header(c: c, title: s["signUpTitle"], onBack: { c.back() })
            ErrorBanner(text: c.errorText)
            Field(label: s["email"], text: $c.email, error: c.emailError, kind: .email, id: "rivium-sign-up-email", submit: .next)
            Field(label: s["password"], text: $c.password, error: c.passwordError, kind: .newPassword, id: "rivium-sign-up-password", submit: .done) {
                c.signUp()
            }
            PrimaryButton(label: s["signUp"], busy: c.busy, id: "rivium-sign-up") { c.signUp() }
                .padding(.top, 4)
            Button(s["haveAccount"]) { c.back() }
                .font(.subheadline)
        }
        .disabled(c.busy)
    }
}

/// One e-mail field and a send button: forgot password and magic link.
@available(iOS 15.0, macOS 12.0, *)
private struct EmailOnlyScreen: View {
    @ObservedObject var c: RiviumSignInController
    let title: String
    let action: String
    let id: String
    let send: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Header(c: c, title: title, onBack: { c.back() })
            ErrorBanner(text: c.errorText)
            Field(label: c.strings["email"], text: $c.email, error: c.emailError, kind: .email, id: "rivium-\(id)-email", submit: .send, onSubmit: send)
            PrimaryButton(label: action, busy: c.busy, id: "rivium-\(id)-send", action: send)
                .padding(.top, 4)
        }
        .disabled(c.busy)
    }
}

/// Telegram: the phone number, then the code (or "open the bot first").
@available(iOS 15.0, macOS 12.0, *)
private struct TelegramScreen: View {
    @ObservedObject var c: RiviumSignInController

    var body: some View {
        let s = c.strings
        let codeStep = c.screen == .telegramCode
        let bot = c.safeBotURL
        VStack(spacing: 12) {
            Header(c: c, title: s["telegramTitle"], onBack: { codeStep ? c.go(.telegramPhone) : c.back() })
            ErrorBanner(text: c.errorText)
            if !codeStep {
                Field(label: s["phone"], hint: s["phoneHint"], text: $c.phone, kind: .phone, id: "rivium-phone", submit: .send) {
                    c.sendTelegramCode()
                }
                if let bot = bot {
                    Text(s["botFirst"].replacingOccurrences(of: "{bot}", with: Self.botName(bot)))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if c.options.openURL != nil {
                            Button(bot.absoluteString) { c.openBot() }
                                .accessibilityIdentifier("rivium-bot-link")
                        } else {
                            Text(bot.absoluteString).textSelection(.enabled)
                        }
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: c.strings.isRightToLeft ? .trailing : .leading)
                }
                PrimaryButton(label: bot != nil ? s["retry"] : s["sendCode"], busy: c.busy, id: "rivium-send-code") {
                    c.sendTelegramCode()
                }
                .padding(.top, 4)
            } else {
                Text(s["codeSent"])
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Field(label: s["code"], text: $c.code, kind: .code, id: "rivium-code", submit: .done) {
                    c.verifyTelegramCode()
                }
                PrimaryButton(label: s["verify"], busy: c.busy, id: "rivium-verify-code") { c.verifyTelegramCode() }
                    .padding(.top, 4)
            }
        }
        .disabled(c.busy)
    }

    static func botName(_ url: URL) -> String {
        let name = url.pathComponents.first { $0 != "/" && !$0.isEmpty }
        return name.map { "@\($0)" } ?? "Telegram"
    }
}

/// "Check your e-mail" after a link was sent, and "sign-in is not available".
@available(iOS 15.0, macOS 12.0, *)
private struct MessageScreen: View {
    @ObservedObject var c: RiviumSignInController

    var body: some View {
        let s = c.strings
        if c.screen == .unavailable {
            VStack(spacing: 16) {
                Header(c: c, title: c.title)
                Text(c.errorText ?? s["noMethods"])
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("rivium-unavailable")
                Button(s["retry"]) { c.load() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        } else {
            let key: String = {
                switch c.sent {
                case .reset: return "resetSent"
                case .magicLink: return "linkSent"
                case .resend: return "resendSent"
                default: return "verifySent"
                }
            }()
            let email = c.email.trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(spacing: 16) {
                Header(c: c, title: s["checkEmail"])
                Image(systemName: "envelope.badge")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
                Text(s[key].replacingOccurrences(of: "{email}", with: "\u{2068}\(email)\u{2069}"))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("rivium-sent")
                Button(s["back"]) { c.back() }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
    }
}

/// Google, Apple, magic link, Telegram and guest (only those on).
@available(iOS 15.0, macOS 12.0, *)
private struct OtherMethods: View {
    @ObservedObject var c: RiviumSignInController

    var body: some View {
        let s = c.strings
        VStack(spacing: 10) {
            if c.showGoogle {
                MethodButton(label: s["withGoogle"], id: "rivium-google", icon: { Text("G").fontWeight(.bold) }) { c.continueWithGoogle() }
            }
            if c.showApple {
                MethodButton(label: s["withApple"], id: "rivium-apple", icon: { Image(systemName: "applelogo") }) { c.continueWithApple() }
            }
            if c.showMagicLink {
                MethodButton(label: s["withEmailLink"], id: "rivium-magic-link", icon: { Image(systemName: "envelope") }) { c.go(.magicLink) }
            }
            if c.showTelegram {
                MethodButton(label: s["withTelegram"], id: "rivium-telegram", icon: { Image(systemName: "paperplane") }) { c.go(.telegramPhone) }
            }
            if c.showGuest {
                Button(s["guest"]) { c.continueAsGuest() }
                    .font(.subheadline)
                    .padding(.top, 2)
                    .accessibilityIdentifier("rivium-guest")
            }
        }
    }
}

// MARK: - Parts

@available(iOS 15.0, macOS 12.0, *)
private struct Header: View {
    @ObservedObject var c: RiviumSignInController
    let title: String
    var onBack: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if let onBack = onBack {
                HStack {
                    Button(action: onBack) {
                        // Mirrors to a right-pointing chevron in a right-to-left language.
                        Image(systemName: "chevron.backward")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(Text(c.strings["back"]))
                    .accessibilityIdentifier("rivium-back")
                    Spacer()
                }
            }
            if let logo = c.options.logo {
                logo.resizable().scaledToFit().frame(maxWidth: 72, maxHeight: 72)
            }
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct ErrorBanner: View {
    let text: String?

    var body: some View {
        if let text = text {
            Text(text)
                .font(.subheadline)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.12)))
                .accessibilityIdentifier("rivium-sign-in-error")
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct Field: View {
    enum Kind { case email, password, newPassword, phone, code }

    let label: String
    var hint: String?
    @Binding var text: String
    var error: String?
    let kind: Kind
    let id: String
    let submit: SubmitLabel
    var onSubmit: (() -> Void)?

    init(label: String, hint: String? = nil, text: Binding<String>, error: String? = nil, kind: Kind, id: String,
         submit: SubmitLabel, onSubmit: (() -> Void)? = nil) {
        self.label = label
        self.hint = hint
        self._text = text
        self.error = error
        self.kind = kind
        self.id = id
        self.submit = submit
        self.onSubmit = onSubmit
    }

    @Environment(\.layoutDirection) private var direction

    /// E-mail, phone and code read left to right, also in a right-to-left language.
    private var ltr: Bool { kind == .email || kind == .phone || kind == .code }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)
            input
                .environment(\.layoutDirection, ltr ? .leftToRight : direction)
                .submitLabel(submit)
                .onSubmit { onSubmit?() }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(error == nil ? Color.secondary.opacity(0.4) : Color.red))
                .accessibilityIdentifier(id)
            if let error = error {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var input: some View {
        let prompt = Text(hint ?? "")
        switch kind {
        case .password, .newPassword:
            SecureField(label, text: $text, prompt: hint == nil ? nil : prompt)
                .textContentTypeIfAvailable(kind == .password ? .password : .newPassword)
        default:
            TextField(label, text: $text, prompt: hint == nil ? nil : prompt)
                .autocorrectionDisabled()
                .plainKeyboard(kind)
        }
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct PrimaryButton: View {
    let label: String
    let busy: Bool
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(label).opacity(busy ? 0 : 1)
                if busy { ProgressView().tint(.white) }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(id)
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct MethodButton<Icon: View>: View {
    let label: String
    let id: String
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon().frame(width: 22)
                Text(label)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityIdentifier(id)
    }
}

@available(iOS 15.0, macOS 12.0, *)
private struct Rule: View {
    var body: some View {
        Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
    }
}

// MARK: - Platform bits

private enum PasswordKind { case password, newPassword }

@available(iOS 15.0, macOS 12.0, *)
private extension View {
    @ViewBuilder func textContentTypeIfAvailable(_ kind: PasswordKind) -> some View {
        #if os(iOS)
        textContentType(kind == .password ? .password : .newPassword)
        #else
        self
        #endif
    }

    @ViewBuilder func plainKeyboard(_ kind: Field.Kind) -> some View {
        #if os(iOS)
        switch kind {
        case .email:
            keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never)
        case .phone:
            keyboardType(.phonePad).textContentType(.telephoneNumber)
        case .code:
            keyboardType(.numberPad).textContentType(.oneTimeCode)
        default:
            textInputAutocapitalization(.never)
        }
        #else
        self
        #endif
    }
}
