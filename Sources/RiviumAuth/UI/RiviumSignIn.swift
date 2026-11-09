#if canImport(UIKit) && !os(watchOS)
import Combine
import SwiftUI
import UIKit

/// Opens Rivium's ready-made sign-in screen, like FirebaseUI.
@available(iOS 15.0, *)
public enum RiviumSignIn {
    /// Opens the sign-in screen and answers the signed-in user, or nil when the user closed it. Full screen on
    /// iPhone, a sheet on iPad (regular width). It cannot be closed while a sign-in runs.
    ///
    /// ```swift
    /// if let result = await RiviumSignIn.present(from: self) {
    ///     print(result.userId)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - presenter: The view controller to present from. nil: the top-most one of the key window.
    ///   - auth: The client to sign in with.
    ///   - options: What the screen offers and how it looks.
    @MainActor
    public static func present(
        from presenter: UIViewController? = nil,
        auth: RiviumAuth = .shared,
        options: RiviumSignInOptions = RiviumSignInOptions(),
        animated: Bool = true
    ) async -> AuthResult? {
        await withCheckedContinuation { continuation in
            present(from: presenter, auth: auth, options: options, animated: animated) { continuation.resume(returning: $0) }
        }
    }

    /// Opens the sign-in screen and calls `completion` once, with the signed-in user or nil when the user closed it.
    @MainActor
    public static func present(
        from presenter: UIViewController? = nil,
        auth: RiviumAuth = .shared,
        options: RiviumSignInOptions = RiviumSignInOptions(),
        animated: Bool = true,
        completion: @escaping (AuthResult?) -> Void
    ) {
        guard let presenter = presenter ?? topViewController() else {
            completion(nil)
            return
        }
        let presentation = SignInPresentation(controller: RiviumSignInController(auth: auth, options: options), completion: completion)
        let host = presentation.makeHost(tint: presenter.view.tintColor, regularWidth: presenter.traitCollection.horizontalSizeClass == .regular)
        presenter.present(host, animated: animated)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }
}

/// One open sign-in screen: answers once, and refuses to close while a sign-in runs.
@available(iOS 15.0, *)
@MainActor
final class SignInPresentation: NSObject, UIAdaptivePresentationControllerDelegate {
    let controller: RiviumSignInController
    private var completion: ((AuthResult?) -> Void)?
    /// The answer once the screen is on its way out.
    private(set) var pending: AuthResult?
    private weak var host: UIViewController?
    private var busyWatch: AnyCancellable?

    init(controller: RiviumSignInController, completion: @escaping (AuthResult?) -> Void) {
        self.controller = controller
        self.completion = completion
        super.init()
        controller.onSignedIn = { [weak self] result in self?.dismiss(with: result) }
    }

    /// The view controller to present: full screen on a phone, a form sheet on a wide screen.
    func makeHost(tint: UIColor?, regularWidth: Bool) -> UIViewController {
        let content = RiviumSignInContent(c: controller, onClose: { [weak self] in self?.dismiss(with: nil) })
            .tint(tint.map(Color.init(uiColor:)))
        let host = SignInHostingController(rootView: AnyView(content), presentation: self)
        host.modalPresentationStyle = regularWidth ? .formSheet : .fullScreen
        host.presentationController?.delegate = self
        busyWatch = controller.$busy.sink { [weak host] busy in host?.isModalInPresentation = busy }
        self.host = host
        return host
    }

    func dismiss(with result: AuthResult?) {
        guard completion != nil, result != nil || controller.canClose else { return }
        pending = result
        guard let host = host, host.presentingViewController != nil else { return finish(result) }
        host.dismiss(animated: true) { [weak self] in self?.finish(result) }
    }

    func finish(_ result: AuthResult?) {
        guard let completion = completion else { return }
        self.completion = nil
        busyWatch = nil
        controller.close()
        completion(result)
    }

    // MARK: UIAdaptivePresentationControllerDelegate

    func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
        controller.canClose
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(nil)
    }
}

/// Keeps its presentation alive and answers nil if it is dismissed some other way.
@available(iOS 15.0, *)
final class SignInHostingController: UIHostingController<AnyView> {
    private let presentation: SignInPresentation

    init(rootView: AnyView, presentation: SignInPresentation) {
        self.presentation = presentation
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || presentingViewController == nil { presentation.finish(presentation.pending) }
    }
}
#endif
