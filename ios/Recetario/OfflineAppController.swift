import UIKit
import WebKit
import UniformTypeIdentifiers
import Vision
import CryptoKit
import UserNotifications
import AVFoundation

@MainActor final class OfflineAppController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate {
    private let database: DeviceDatabase
    private var webView: WKWebView!
    private let bundle: OfflineBundleHandler
    private let ai = DeviceAIClient()
    private let timers = DeviceTimers()
    private let speech = AVSpeechSynthesizer()
    private var pendingSource: URL?
    private var pendingText = ""
    private var importReady = false
    private var cooking = false
    init(database: DeviceDatabase) throws {
        self.database = database
        guard let directory = Bundle.main.url(forResource: "OfflineApp", withExtension: nil) else { throw LocalRecipeError.invalid("Faltan los archivos de la app. Conserva tus datos y actualiza la instalación.") }
        bundle = OfflineBundleHandler(directory: directory)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = LocalRecipeStyle.background
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.setURLSchemeHandler(bundle, forURLScheme: "recetario-local")
        configuration.userContentController.addScriptMessageHandler(OfflineBridge(owner: self), contentWorld: .page, name: "device")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.isOpaque = false; webView.backgroundColor = view.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
        loadApp()
    }
    private func loadApp() {
        importReady = false
        var url = URLComponents(string: "recetario-local://bundle/mobile/index.html")!
        if let pendingSource { url.queryItems = [URLQueryItem(name: "url", value: pendingSource.absoluteString), URLQueryItem(name: "text", value: pendingText)] }
        webView.load(URLRequest(url: url.url!)); pendingSource = nil; pendingText = ""
    }
    func openImportSource(_ source: URL, text: String = "") {
        pendingSource = source; pendingText = text
        guard isViewLoaded, importReady else { return }
        // Avoid reloading or losing a currently open editor.
        webView.callAsyncJavaScript("window.dispatchEvent(new CustomEvent('recetario-native-import',{detail:{url:source,text:caption}}));", arguments: ["source": source.absoluteString, "caption": text], in: nil, in: .page) { _ in }
        pendingSource = nil; pendingText = ""
    }
    @objc private func background() { UIApplication.shared.isIdleTimerDisabled = false; speech.stopSpeaking(at: .immediate) }
    @objc private func foreground() { UIApplication.shared.isIdleTimerDisabled = cooking }
    private func trusted(_ url: URL?) -> Bool { url?.scheme == "recetario-local" && url?.host == "bundle" && ["/", "/mobile/index.html"].contains(url?.path ?? "") }
    func receive(_ message: WKScriptMessage, reply: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, trusted(message.frameInfo.request.url), trusted(webView.url), let body = message.body as? [String: Any], let action = body["action"] as? String else { reply(nil, "Origen no permitido."); return }
        Task {
            do { let value = try await perform(action, body); reply(["ok": true, "value": value], nil) }
            catch { reply(["ok": false, "error": error.localizedDescription], nil) }
        }
    }
    private func perform(_ action: String, _ body: [String: Any]) async throws -> Any {
        switch action {
        case "sql":
            guard let statements = body["statements"] as? [[String: Any]] else { throw LocalRecipeError.invalid("Faltan los datos locales.") }
            return try await database.execute(statements)
        case "kv-read": return try await database.keyValues()
        case "kv-write":
            guard let key = body["key"] as? String else { throw LocalRecipeError.invalid("No se puede guardar el borrador.") }
            try await database.writeKey(key, value: body["value"] as? String); return true
        case "hash":
            guard let raw = body["bytes"] as? String, let bytes = Data(base64Encoded: raw), bytes.count < 16_000_000 else { throw LocalRecipeError.invalid("Los datos son demasiado grandes.") }
            return Data(SHA256.hash(data: bytes)).base64EncodedString()
        case "ai-status":
            let values=try await database.keyValues()
            guard DeviceAIConsent.granted(values[DeviceAIConsent.key]) else { return ["ai":false,"enabled":false,"requiresConsent":true,"reason":"La ayuda de IA está desactivada. Tus recetas locales siguen disponibles."] as [String:Any] }
            return await ai.status()
        case "ai-request":
            let values=try await database.keyValues()
            guard DeviceAIConsent.granted(values[DeviceAIConsent.key]) else { throw LocalRecipeError.invalid("Da permiso antes de enviar contenido a la ayuda de IA. Tus recetas locales siguen disponibles.") }
            return try await ai.request(body)
        case "recognize":
            guard let images = body["images"] as? [String], images.count <= 12 else { throw LocalRecipeError.invalid("Demasiadas imágenes.") }
            return try await recognize(images)
        case "share":
            guard let text = body["text"] as? String, text.utf8.count <= 100_000 else { throw LocalRecipeError.invalid("El texto es demasiado largo.") }
            share([text]); return true
        case "clipboard":
            guard let text = body["text"] as? String, text.utf8.count <= 100_000 else { throw LocalRecipeError.invalid("El texto es demasiado largo.") }
            UIPasteboard.general.string = text; return true
        case "clipboard-read":
            guard UIApplication.shared.applicationState == .active else { throw LocalRecipeError.invalid("Abre la app para pegar un enlace.") }
            return UIPasteboard.general.string ?? ""
        case "navigation":
            cooking = body["keepAwake"] as? Bool == true
            UIApplication.shared.isIdleTimerDisabled = cooking && UIApplication.shared.applicationState == .active
            return true
        case "timers":
            guard let id = body["id"] as? String, let title = body["title"] as? String, let values = body["timers"] as? [String: Any] else { throw LocalRecipeError.invalid("Faltan los temporizadores.") }
            try await timers.update(id: id, title: title, timers: values); return true
        case "speak":
            speech.stopSpeaking(at: .immediate)
            if let text = body["text"] as? String, !text.isEmpty, text.utf8.count <= 24000 {
                let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: "es-ES"); speech.speak(utterance)
            }
            return true
        case "backup-export": try await exportBackup(); return true
        case "export-json":
            guard let data = body["data"], JSONSerialization.isValidJSONObject(data), presentedViewController == nil else { throw LocalRecipeError.invalid("No se pudo preparar la exportación.") }
            let bytes = try JSONSerialization.data(withJSONObject: data)
            try exportJSON(bytes, name: "Recetario-recetas.json"); return true
        case "print":
            guard presentedViewController == nil else { throw LocalRecipeError.invalid("Cierra la ventana actual antes de imprimir.") }
            let controller = UIPrintInteractionController.shared
            controller.printFormatter = webView.viewPrintFormatter()
            controller.present(from: CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), in: view, animated: true, completionHandler: nil)
            return true
        case "backup-import":
            guard presentedViewController == nil else { throw LocalRecipeError.invalid("Cierra la ventana actual antes de abrir una copia.") }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
            picker.delegate = self; present(picker, animated: true); return true
        case "legacy-read":
            let store = try LocalRecipeStore()
            var values: [[String: Any]] = []
            for recipe in store.visible {
                let encoded = try JSONEncoder().encode(recipe)
                var value = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
                if let id = recipe.photoID { value["legacyPhoto"] = "data:image/jpeg;base64," + (try store.photoData(id)).base64EncodedString() }
                values.append(value)
            }
            return values
        default: throw LocalRecipeError.invalid("Operación no permitida.")
        }
    }
    private func recognize(_ images: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            var result: [String] = []
            for raw in images {
                guard let bytes = Data(base64Encoded: raw), bytes.count <= 4_000_000 else { throw LocalRecipeError.invalid("Imagen no válida.") }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate; request.recognitionLanguages = ["es-ES", "en-US"]; request.usesLanguageCorrection = true
                try VNImageRequestHandler(data: bytes, options: [:]).perform([request])
                result.append((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
            }
            return result.joined(separator: "\n\n")
        }.value
    }
    private func share(_ items: [Any], cleanup: URL? = nil) {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = view
        controller.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        if let cleanup { controller.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: cleanup) } }
        present(controller, animated: true)
    }
    private func exportBackup() async throws {
        guard presentedViewController == nil else { throw LocalRecipeError.invalid("Cierra la ventana actual antes de exportar.") }
        let value = try await webView.callAsyncJavaScript("return await window.__recetarioExport();", arguments: [:], in: nil, contentWorld: .page)
        guard let value, JSONSerialization.isValidJSONObject(value) else { throw LocalRecipeError.invalid("No se pudo preparar la copia completa.") }
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard bytes.count <= LocalRecipeStore.maximumBackupBytes else { throw LocalRecipeError.invalid("La copia supera los 128 MB admitidos.") }
        try exportJSON(bytes, name: "Recetario-copia-completa.json")
    }
    private func exportJSON(_ bytes: Data, name: String) throws {
        guard bytes.count <= LocalRecipeStore.maximumBackupBytes else { throw LocalRecipeError.invalid("La copia supera los 128 MB admitidos.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        share([file], cleanup: directory)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let file = urls.first else { return }
        Task {
            do {
                let scoped = file.startAccessingSecurityScopedResource(); defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                guard let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize <= LocalRecipeStore.maximumBackupBytes else { throw LocalRecipeError.invalid("La copia supera los 128 MB admitidos.") }
                let value = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                let summary = try await webView.callAsyncJavaScript("return await window.__recetarioInspect(value);", arguments: ["value": value], in: nil, contentWorld: .page) as? [String: Any]
                let count = summary?["recipes"] as? Int ?? 0
                let alert = UIAlertController(title: "Importar \(count) recetas", message: "Se añadirán como espacios nuevos, con su menú, despensa, compra y fotos. Tus datos actuales se conservan.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel))
                for (title, tastes) in [("Añadir y conservar mis gustos", false), ("Añadir y restaurar gustos de la copia", true)] {
                    alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in self?.restoreBackup(value, tastes: tastes) })
                }
                present(alert, animated: true)
            } catch { inform(error.localizedDescription) }
        }
    }
    private func restoreBackup(_ value: Any, tastes: Bool) {
        Task {
            do {
                _ = try await webView.callAsyncJavaScript("return await window.__recetarioRestore(value,tastes);", arguments: ["value": value, "tastes": tastes], in: nil, contentWorld: .page)
                inform("Copia importada. Los espacios anteriores se conservan.")
            } catch { inform("No se pudo importar la copia. Tus datos actuales se conservan.\n" + error.localizedDescription) }
        }
    }
    private func inform(_ message: String) {
        let alert = UIAlertController(title: "Recetario", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Aceptar", style: .default)); present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        view.backgroundColor = LocalRecipeStyle.background
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<240 {
                if (try? await webView.evaluateJavaScript("window.__recetarioImportReady === 1")) as? Bool == true {
                    self.importReady = true
                    if let source = self.pendingSource { self.openImportSource(source, text: self.pendingText) }
                    return
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { inform("La vista se ha cerrado. Tus recetas guardadas se conservan. Abre de nuevo la app.") }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if trusted(url) { decisionHandler(.allow); return }
        if action.targetFrame?.isMainFrame == false && NavigationPolicy.isVideoEmbed(url) { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated && (["https", "http", "mailto"].contains(url.scheme ?? "") || url.absoluteString == "shortcuts://create-shortcut") { UIApplication.shared.open(url) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, (["https", "http", "mailto"].contains(url.scheme ?? "") || url.absoluteString == "shortcuts://create-shortcut") { UIApplication.shared.open(url) }
        return nil
    }
}

@MainActor private final class OfflineBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var owner: OfflineAppController?
    init(owner: OfflineAppController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let owner else { replyHandler(nil, "La vista se ha cerrado."); return }
        owner.receive(message, reply: replyHandler)
    }
}

final class OfflineBundleHandler: NSObject, WKURLSchemeHandler {
    let directory: URL
    init(directory: URL) { self.directory = directory.standardizedFileURL }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        do {
            guard let url = urlSchemeTask.request.url, url.scheme == "recetario-local", url.host == "bundle" else { throw URLError(.unsupportedURL) }
            let path = url.path == "/" ? "mobile/index.html" : String(url.path.dropFirst())
            let file = directory.appendingPathComponent(path).standardizedFileURL
            guard file.path.hasPrefix(directory.path + "/"), !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else { throw URLError(.noPermissionsToReadFile) }
            let bytes = try Data(contentsOf: file)
            let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(url: url, mimeType: file.pathExtension == "js" ? "application/javascript" : type, expectedContentLength: bytes.count, textEncodingName: ["html", "css", "js", "json"].contains(file.pathExtension) ? "utf-8" : nil)
            urlSchemeTask.didReceive(response); urlSchemeTask.didReceive(bytes); urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
