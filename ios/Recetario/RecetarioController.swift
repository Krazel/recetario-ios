import UIKit
import WebKit
import SafariServices
import AuthenticationServices

@MainActor final class RecetarioController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UITabBarDelegate, ASWebAuthenticationPresentationContextProviding {
    private(set) var webView: WKWebView!
    private let progress = UIProgressView(progressViewStyle: .default)
    private var observation: NSKeyValueObservation?
    private let retry = UIButton(type: .system)
    private var initialURL = NavigationPolicy.origin
    private let tabBar = UITabBar()
    private var tabHeight: NSLayoutConstraint!
    private var contentBottom: NSLayoutConstraint!
    private var nativeState: NativeNavigationState?
    private var keyboardVisible = false
    private var bridgeAcknowledged = false
    private var authSession: ASWebAuthenticationSession?
    private var signIn: NativeSignIn?
    private var exchangingSession = false
    private let welcome = UIStackView()
    private let signInButton = UIButton(type: .system)
    private let signInMessage = UILabel()
    private let accent = UIColor(red: 0.73, green: 0.17, blue: 0.15, alpha: 1)
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1)
        overrideUserInterfaceStyle = .light
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(WeakScriptHandler(self), name: "recetario")
        let bootstrap = """
        if(location.origin === '\(NavigationPolicy.origin.absoluteString)') {
          window.__recetarioIOS = 1;
          const originalFetch = window.fetch;
          window.fetch = async function(...args) {
            const result = await originalFetch.apply(this, args);
            if(result.headers.get('X-Recetario-Session') === 'expired' && new URL(result.url).origin === location.origin)
              window.webkit.messageHandlers.recetario.postMessage({action:'sessionExpired'});
            return result;
          };
        }
        """
        config.userContentController.addUserScript(WKUserScript(source: bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.delegate = self
        tabBar.accessibilityIdentifier = "recetario.nativeTabs"
        tabBar.items = NativeSection.allCases.enumerated().map { index, section in
            let item = UITabBarItem(title: section.title, image: UIImage(systemName: section.symbol), tag: index)
            item.accessibilityIdentifier = "recetario.tab." + section.rawValue
            return item
        }
        tabBar.selectedItem = tabBar.items?.first
        tabBar.tintColor = accent
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = view.backgroundColor
        appearance.stackedLayoutAppearance.selected.iconColor = accent
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        view.addSubview(tabBar)
        tabHeight = tabBar.heightAnchor.constraint(equalToConstant: 0)
        contentBottom = webView.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
        contentBottom.priority = UILayoutPriority(999)
        tabBar.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progress)
        retry.setTitle("No se pudo abrir Recetario. Toca para reintentar", for: .normal)
        retry.titleLabel?.numberOfLines = 0
        retry.titleLabel?.textAlignment = .center
        retry.addTarget(self, action: #selector(reload), for: .touchUpInside)
        retry.isHidden = true
        retry.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(retry)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentBottom,
            webView.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor), tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor), tabHeight,
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor), webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            progress.topAnchor.constraint(equalTo: webView.topAnchor), progress.leadingAnchor.constraint(equalTo: view.leadingAnchor), progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            retry.centerYAnchor.constraint(equalTo: view.centerYAnchor), retry.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), retry.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28)
        ])
        configureWelcome()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        observation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
            Task { @MainActor [weak self] in self?.progress.progress = Float(web.estimatedProgress); self?.progress.isHidden = web.estimatedProgress >= 1 }
        }
        open(initialURL)
    }
    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange(); updateChrome() }
    private func updateChrome() {
        guard isViewLoaded, tabHeight != nil else { return }
        let show = nativeState?.visible == true && NavigationPolicy.isTrusted(webView.url) && !keyboardVisible
        tabBar.isHidden = !show
        // The native bar owns the home-indicator inset. Web content receives no second bottom inset.
        tabHeight.constant = show ? 49 + view.safeAreaInsets.bottom : view.safeAreaInsets.bottom
        UIApplication.shared.isIdleTimerDisabled = nativeState?.keepAwake == true && UIApplication.shared.applicationState == .active && NavigationPolicy.isTrusted(webView.url)
    }
    @objc private func keyboardChanged(_ note: Notification) {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let local = view.convert(frame, from: nil)
        keyboardVisible = view.bounds.intersection(local).height > view.safeAreaInsets.bottom + 80
        updateChrome()
    }
    @objc private func enteredBackground() { UIApplication.shared.isIdleTimerDisabled = false }
    @objc private func becameActive() { updateChrome() }
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard NativeSection.allCases.indices.contains(item.tag), NavigationPolicy.isTrusted(webView.url) else { return }
        let section = NativeSection.allCases[item.tag]
        UISelectionFeedbackGenerator().selectionChanged()
        webView.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('recetario-native-tab',{detail:{section:section}}));", arguments: ["section": section.rawValue], in: nil, in: .page) { _ in }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        nativeState = nil; bridgeAcknowledged = false; updateChrome()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        retry.isHidden = true; updateChrome()
        if exchangingSession {
            exchangingSession = false; signInButton.isEnabled = true
            welcome.isHidden = true; webView.isHidden = false
            if initialURL.path != "" && initialURL.path != "/" { open(initialURL) }
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
            if http.statusCode == 401 { decisionHandler(.cancel); showSignIn(exchangingSession ? "La conexión ha caducado. Vuelve a intentarlo." : nil); return }
            if http.statusCode >= 400 { decisionHandler(.cancel); exchangingSession = false; signInButton.isEnabled = true; retry.isHidden = false; return }
        }
        decisionHandler(.allow)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { nativeState = nil; updateChrome(); retry.isHidden = false }
    func open(_ url: URL) {
        guard NavigationPolicy.isTrusted(url) else { return }
        initialURL = url
        guard isViewLoaded else { return }
        retry.isHidden = true
        welcome.isHidden = true; webView.isHidden = false
        webView.load(URLRequest(url: url))
    }
    @objc private func reload() { open(initialURL) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { retry.isHidden = false } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if (error as NSError).code != NSURLErrorCancelled { retry.isHidden = false } }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if NavigationPolicy.isTrusted(url), url.path == "/signout-with-chatgpt" {
            decisionHandler(.cancel); signOut(); return
        }
        if (NavigationPolicy.isTrusted(url) && url.path == "/signin-with-chatgpt") || url.host == NavigationPolicy.signInOrigin.host {
            decisionHandler(.cancel); showSignIn(); beginSignIn(); return
        }
        if NavigationPolicy.isTrusted(url) { decisionHandler(.allow); return }
        if action.targetFrame?.isMainFrame == false, NavigationPolicy.isVideoEmbed(url) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { present(SFSafariViewController(url: url), animated: true) }
        else if action.navigationType == .linkActivated, url.scheme == "mailto" { UIApplication.shared.open(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, NavigationPolicy.isTrusted(url) { webView.load(action.request) }
        else if let url = action.request.url, url.scheme == "https" { present(SFSafariViewController(url: url), animated: true) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard NavigationPolicy.isTrusted(frame.request.url), presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: "Recetario", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard NavigationPolicy.isTrusted(frame.request.url), presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: "Recetario", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, NavigationPolicy.isTrusted(webView.url),
              message.frameInfo.securityOrigin.protocol == "https", message.frameInfo.securityOrigin.host == NavigationPolicy.origin.host,
              [0,443].contains(message.frameInfo.securityOrigin.port), let body = message.body as? [String: Any] else { return }
        if let state = NativeNavigationState(body) {
            nativeState = state
            if let index = NativeSection.allCases.firstIndex(of: state.section) { tabBar.selectedItem = tabBar.items?[index] }
            updateChrome()
            if !bridgeAcknowledged {
                bridgeAcknowledged = true
                webView.evaluateJavaScript("window.dispatchEvent(new Event('recetario-native-ready'));")
            }
        } else if body["action"] as? String == "sessionExpired" {
            showSignIn("Tu sesión ha caducado. Vuelve a entrar para continuar.")
        } else if body["action"] as? String == "subscription", presentedViewController == nil {
            present(UINavigationController(rootViewController: SubscriptionController(webView: webView)), animated: true)
        }
    }
    private func configureWelcome() {
        welcome.axis = .vertical; welcome.spacing = 22; welcome.alignment = .fill
        welcome.translatesAutoresizingMaskIntoConstraints = false; welcome.isHidden = true
        let brand = UILabel(); brand.text = "Recetario"; brand.font = .systemFont(ofSize: 36, weight: .bold); brand.textColor = accent
        let subtitle = UILabel(); subtitle.text = "Tu cocina, a tu manera"; subtitle.font = .preferredFont(forTextStyle: .title2)
        signInMessage.text = "Accede a tus recetas, tu menú y tu compra."; signInMessage.numberOfLines = 0; signInMessage.textColor = .secondaryLabel
        signInButton.setTitle("Continuar con ChatGPT", for: .normal); signInButton.setTitleColor(.white, for: .normal)
        signInButton.backgroundColor = accent; signInButton.layer.cornerRadius = 16
        signInButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        signInButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        signInButton.addTarget(self, action: #selector(beginSignIn), for: .touchUpInside)
        [brand,subtitle,signInMessage,signInButton].forEach(welcome.addArrangedSubview)
        view.addSubview(welcome)
        NSLayoutConstraint.activate([welcome.centerYAnchor.constraint(equalTo:view.safeAreaLayoutGuide.centerYAnchor),welcome.centerXAnchor.constraint(equalTo:view.centerXAnchor),welcome.widthAnchor.constraint(lessThanOrEqualToConstant:420),welcome.leadingAnchor.constraint(greaterThanOrEqualTo:view.safeAreaLayoutGuide.leadingAnchor,constant:28),welcome.trailingAnchor.constraint(lessThanOrEqualTo:view.safeAreaLayoutGuide.trailingAnchor,constant:-28)])
        let width = welcome.widthAnchor.constraint(equalTo:view.safeAreaLayoutGuide.widthAnchor,constant:-56); width.priority = .defaultHigh; width.isActive = true
    }
    private func showSignIn(_ message: String? = nil) {
        webView.stopLoading(); webView.isHidden = true; welcome.isHidden = false; retry.isHidden = true
        nativeState = nil; exchangingSession = false; updateChrome(); progress.isHidden = true
        signInButton.isEnabled = authSession == nil
        signInMessage.text = message ?? "Accede a tus recetas, tu menú y tu compra."
    }
    @objc private func beginSignIn() {
        guard authSession == nil else { return }
        guard let attempt = try? NativeSignIn() else { showSignIn("No se pudo iniciar la conexión. Inténtalo de nuevo."); return }
        signIn = attempt; signInButton.isEnabled = false
        signInMessage.text = "Código de conexión: \(attempt.displayCode). Comprueba que coincide al continuar."
        let session = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: "krazel-recetario") { [weak self] callback,error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.authSession = nil; self.signInButton.isEnabled = true
                guard error == nil, let callback, let active = self.signIn, let request = active.exchangeRequest(callback:callback) else {
                    self.signIn = nil
                    self.showSignIn((error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ? "Puedes iniciar sesión cuando quieras." : "No se pudo completar la conexión. Vuelve a intentarlo.")
                    return
                }
                self.signIn = nil; self.exchangingSession = true
                self.signInMessage.text = "Abriendo tu recetario…"; self.signInButton.isEnabled = false
                // The exchange runs in WKWebView, so its HttpOnly cookie belongs to the app's persistent store.
                self.webView.load(request)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        if !session.start() { authSession = nil; signIn = nil; showSignIn("No se pudo abrir el acceso. Inténtalo de nuevo.") }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { view.window ?? ASPresentationAnchor() }
    private func signOut() {
        guard NavigationPolicy.isTrusted(webView.url) else { return }
        webView.callAsyncJavaScript("const r = await fetch('/native/logout',{method:'POST'}); if(!r.ok) throw new Error('logout');", arguments:[:], in:nil, in:.page) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success: self.initialURL = NavigationPolicy.origin; self.showSignIn("Has cerrado sesión en este iPhone.")
                case .failure: self.retry.isHidden = false
                }
            }
        }
    }
}

@MainActor private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: RecetarioController?
    init(_ owner: RecetarioController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.userContentController(userContentController, didReceive: message) }
}
