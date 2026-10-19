import SwiftUI
import RiviumAuth

// Rivium Auth — iOS example (SDK 0.1.1)
//
// Paste your public project key (Rivium Console → your project → API keys) into the field,
// or replace the placeholder below. Never put a server secret in an app.
// In a real app call RiviumAuth.shared.configure(apiKey:) once, at app start.

private let apiKeyPlaceholder = "rv_live_YOUR_PUBLIC_KEY"

@MainActor
final class AuthModel: ObservableObject {
    @Published var apiKey = apiKeyPlaceholder
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var userId: String?
    @Published private(set) var status = ""
    @Published private(set) var isConfigured = false
    @Published private(set) var isBusy = false

    private let auth = RiviumAuth.shared
    private var listener: RiviumAuthListener?

    func configure() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != apiKeyPlaceholder else {
            status = "Paste your public API key, then tap Configure."
            return
        }
        listener?.remove()
        auth.configure(apiKey: key)
        // Called on sign-in, sign-out and when a session ends.
        listener = auth.addAuthStateListener { [weak self] userId in
            Task { @MainActor in self?.userId = userId }
        }
        userId = auth.currentUserId
        isConfigured = true
        status = "Configured."
    }

    func signInAnonymously() {
        run { _ = try await $0.signInAnonymously(); return "Signed in anonymously." }
    }

    func signUp() {
        let email = email.trimmingCharacters(in: .whitespaces), password = password
        run {
            let result = try await $0.signUp(email: email, password: password)
            return result.signedIn ? "Signed up." : "Check your inbox: confirm the e-mail, then sign in."
        }
    }

    func signIn() {
        let email = email.trimmingCharacters(in: .whitespaces), password = password
        run { _ = try await $0.signIn(email: email, password: password); return "Signed in with e-mail." }
    }

    func signOut() {
        run { await $0.signOut(); return "Signed out." }
    }

    func deleteAccount() {
        run { try await $0.deleteAccount(); return "Account deleted." }
    }

    /// Runs one SDK call and shows its result or its error code.
    private func run(_ action: @escaping (RiviumAuth) async throws -> String) {
        isBusy = true
        status = "Working…"
        Task {
            defer { isBusy = false }
            do {
                status = try await action(auth)
            } catch let error as RiviumAuthError {
                status = "\(error.code): \(error.message)"
            } catch {
                status = error.localizedDescription
            }
            userId = auth.currentUserId
        }
    }
}

struct AuthTestView: View {
    @StateObject private var model = AuthModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Public API key (rv_live_...)", text: $model.apiKey)
                        .plainInput()
                    Button("Configure", action: model.configure)
                }

                Section("Current user") {
                    Text(model.userId ?? "signed out")
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    if !model.status.isEmpty {
                        Text(model.status).foregroundStyle(.secondary)
                    }
                }

                Section("Anonymous") {
                    Button("Sign in anonymously", action: model.signInAnonymously)
                }

                Section("E-mail and password") {
                    TextField("E-mail", text: $model.email)
                        .plainInput(email: true)
                    SecureField("Password", text: $model.password)
                    Button("Sign up", action: model.signUp)
                    Button("Sign in", action: model.signIn)
                }

                Section("Account") {
                    Button("Sign out", action: model.signOut)
                    Button("Delete account", role: .destructive, action: model.deleteAccount)
                }
            }
            .disabled(model.isBusy)
            .navigationTitle("Rivium Auth")
            .onAppear { model.configure() }
        }
    }
}

private extension View {
    /// No auto-capitalisation or autocorrection (keys and e-mail addresses).
    func plainInput(email: Bool = false) -> some View {
        #if os(iOS)
        return self
            .keyboardType(email ? .emailAddress : .default)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        return autocorrectionDisabled()
        #endif
    }
}
