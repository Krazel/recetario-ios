import UIKit
import StoreKit
import WebKit

@MainActor final class SubscriptionController: UIViewController {
    private weak var webView: WKWebView?
    private let stack = UIStackView()
    private let status = UILabel()
    private var token: UUID?
    private var products: [Product] = []
    private var ready = false
    private var busy = false
    private var updates: Task<Void, Never>?
    static let productIDs: Set<String> = ["com.krazel.recetario.plus.monthly", "com.krazel.recetario.plus.annual"]
    init(webView: WKWebView) { self.webView = webView; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { updates?.cancel() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Recetario Plus"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll); scroll.addSubview(stack)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30), stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24), stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)])
        status.numberOfLines = 0; status.font = .preferredFont(forTextStyle: .body)
        Task { await load() }
        updates = Task { [weak self] in
            for await result in Transaction.updates { guard !Task.isCancelled else { break }; await self?.accept(result) }
        }
    }
    private func label(_ text: String, style: UIFont.TextStyle = .body) -> UILabel { let l = UILabel(); l.text = text; l.numberOfLines = 0; l.font = .preferredFont(forTextStyle: style); l.adjustsFontForContentSizeCategory = true; return l }
    private func button(_ title: String, _ action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.tinted(); config.title = title; config.cornerStyle = .large
        let b = UIButton(configuration: config, primaryAction: UIAction { _ in action() }); b.configuration?.titleLineBreakMode = .byWordWrapping; b.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true; return b
    }
    private func api(_ body: [String: String]? = nil) async throws -> [String: Any] {
        guard let webView, NavigationPolicy.isTrusted(webView.url) else { throw NSError(domain: "Recetario", code: 1, userInfo: [NSLocalizedDescriptionKey: "Abre tu recetario e inicia sesión primero."]) }
        let script = "const r=await fetch('/api/subscription',body?{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}:{cache:'no-store'});const d=await r.json();if(!r.ok)throw new Error(d.error||'No se pudo verificar');return d;"
        let result = try await webView.callAsyncJavaScript(script, arguments: ["body": body as Any? ?? NSNull()], in: nil, contentWorld: .page)
        guard let d = result as? [String: Any] else { throw NSError(domain: "Recetario", code: 2) }
        return d
    }
    private func load() async {
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v); v.removeFromSuperview() }
        stack.addArrangedSubview(label("Tu semana, un poco más fácil.", style: .largeTitle))
        stack.addArrangedSubview(label("100 lecturas de recetas y 30 propuestas de IA al mes. Menús editables, despensa y compra juntos."))
        stack.addArrangedSubview(status); status.text = "Consultando Apple…"
        do {
            let account = try await api(); token = (account["accountToken"] as? String).flatMap(UUID.init(uuidString:)); ready = account["ready"] as? Bool == true
            products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price }
            status.text = ready ? "Suscripción gestionada por Apple. Conservas tus recetas al cancelar." : "Las compras aún están en preparación. No se puede iniciar ningún cobro."
            for product in products {
                let annual = product.id.hasSuffix("annual")
                let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
                let offer = product.subscription?.introductoryOffer
                let freeWeek = eligible && offer?.paymentMode == .freeTrial && offer?.period.unit == .day && offer?.period.value == 7
                let period = annual ? "año" : "mes"
                let title = (freeWeek ? "7 días gratis; después " : "") + product.displayPrice + "/" + period
                let b = button(title) { [weak self] in Task { await self?.buy(product) } }; b.isEnabled = ready && token != nil
                stack.addArrangedSubview(b)
            }
            if products.isEmpty { stack.addArrangedSubview(label("Apple todavía no devuelve los productos de Recetario. Los precios aparecerán aquí cuando estén configurados.")) }
        } catch { status.text = "No se pudo conectar con la cuenta o con Apple. \(error.localizedDescription)"; ready = false }
        stack.addArrangedSubview(label("Renovación automática hasta que canceles desde tu cuenta de Apple. Si la oferta está disponible, Apple muestra su duración y el siguiente cobro antes de confirmar. Cuotas por mes natural UTC; cada solicitud cuenta aunque no se complete. Tus recetas guardadas no se borran.", style: .footnote))
        stack.addArrangedSubview(button("Restaurar compras") { [weak self] in Task { await self?.restore() } })
        stack.addArrangedSubview(button("Gestionar suscripción en Apple") { [weak self] in Task { guard let scene = self?.view.window?.windowScene else { return }; do { try await AppStore.showManageSubscriptions(in: scene) } catch { self?.status.text = "No se pudo abrir la gestión de Apple." } } })
        stack.addArrangedSubview(button("Condiciones de Apple") { UIApplication.shared.open(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) })
        stack.addArrangedSubview(label("Privacidad y soporte comercial: pendientes de publicación antes de habilitar compras.", style: .footnote))
    }
    private func buy(_ product: Product) async {
        guard !busy, ready, let token else { return }; busy = true; defer { busy = false }
        do { switch try await product.purchase(options: [.appAccountToken(token)]) {
        case .success(let result): await accept(result)
        case .pending: status.text = "Compra pendiente de aprobación en Apple. Aún no hay acceso Plus."
        case .userCancelled: status.text = "Compra cancelada. No se ha activado Plus."
        @unknown default: status.text = "Estado de compra desconocido; puedes restaurarla más tarde."
        }} catch { status.text = "No se pudo completar la compra: \(error.localizedDescription)" }
    }
    private func accept(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID) else { status.text = "No se pudo verificar la compra."; return }
        do {
            let verified = try await api(["action": "sync", "jws": result.jwsRepresentation])
            status.text = verified["plus"] as? Bool == true ? "Plus verificado y vinculado a tu recetario." : "Compra comprobada. No hay un período Plus activo."
            await transaction.finish()
        } catch { status.text = "Apple recibió la compra, pero falta sincronizarla con Recetario. Usa Restaurar compras; no vuelvas a comprar." }
    }
    private func restore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await AppStore.sync(); var found = false
            for await result in Transaction.currentEntitlements { if case .verified(let t) = result, Self.productIDs.contains(t.productID) { found = true; await accept(result) } }
            if !found { status.text = "Apple no devuelve una suscripción activa para esta cuenta." }
        } catch { status.text = "No se pudieron restaurar las compras. Inténtalo de nuevo desde tu cuenta de Apple." }
    }
}
