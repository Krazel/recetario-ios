import Foundation
import DeviceCheck
import CryptoKit
import Security

actor DeviceAIClient {
    private var busy = false
    private let session: URLSession
    private let redirects = RejectAIRedirects()
    private let keyService = "com.krazel.recetario.app-attest"
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 120; configuration.timeoutIntervalForResource = 150
        session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
    }
    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RecetarioAIEndpoint") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
    func status() async -> [String: Any] {
        guard endpoint != nil else { return ["ai": false, "enabled": false, "reason": "La conexión de IA aún no está activada. Tus recetas locales siguen disponibles."] }
        guard DCAppAttestService.shared.isSupported else { return ["ai": false, "enabled": false, "reason": "La IA necesita verificar esta instalación en un iPhone compatible. El resto de la app funciona sin conexión."] }
        do {
            let reply = try await request(["path": "/api/native/budget", "method": "GET", "body": "", "contentType": ""])
            guard let body = reply["body"] as? String, let data = Data(base64Encoded: body), let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LocalRecipeError.invalid("No se pudo comprobar la IA.") }
            return value
        } catch { return ["ai": false, "enabled": false, "reason": error.localizedDescription] }
    }
    func request(_ input: [String: Any]) async throws -> [String: Any] {
        guard let endpoint else { throw LocalRecipeError.invalid("La IA aún no está activada. Puedes seguir guardando, cocinando y organizando recetas sin conexión.") }
        guard DCAppAttestService.shared.isSupported else { throw LocalRecipeError.invalid("Esta instalación no permite verificar el acceso seguro a la IA. Tus recetas locales siguen disponibles.") }
        guard !busy else { throw LocalRecipeError.invalid("Hay otra petición de IA en curso. Espera a que termine.") }
        busy = true; defer { busy = false }
        guard let path = input["path"] as? String, ["/api/import", "/api/assistant", "/api/assistant/image", "/api/native/budget"].contains(path),
              let method = input["method"] as? String, ["GET", "POST"].contains(method),
              let raw = input["body"] as? String, let bytes = Data(base64Encoded: raw), bytes.count <= 12_000_000 else { throw LocalRecipeError.invalid("Petición de IA no válida.") }
        let key = try await enrolledKey(endpoint)
        let challenge = try await post(endpoint.appendingPathComponent("challenge"), value: ["purpose": "request", "keyId": key])
        guard let challengeId = challenge["id"] as? String, let nonce = challenge["challenge"] as? String else { throw LocalRecipeError.invalid("No se pudo verificar el acceso a la IA.") }
        var payload: [String: Any] = ["requestId": UUID().uuidString.lowercased(), "challengeId": challengeId, "challenge": nonce, "path": path, "method": method, "body": raw, "contentType": input["contentType"] as? String ?? ""]
        if let context = input["context"] { payload["context"] = context }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= 17_000_000 else { throw LocalRecipeError.invalid("La petición contiene demasiado material. Selecciona menos recetas o un vídeo más corto.") }
        let assertion = try await DCAppAttestService.shared.generateAssertion(key, clientDataHash: Data(SHA256.hash(data: data)))
        var request = URLRequest(url: endpoint.appendingPathComponent("request")); request.httpMethod = "POST"; request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Recetario-Key")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Recetario-Assertion")
        let (responseData, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, responseData.count <= 30_000_000, (200...599).contains(response.statusCode) else { throw LocalRecipeError.invalid("La respuesta de IA no es válida. No se reintentará automáticamente.") }
        // Uncertain network failures are never retried automatically or sent to a
        // different host. The server retains the cost reservation if needed.
        return ["status": response.statusCode, "contentType": response.value(forHTTPHeaderField: "Content-Type") ?? "application/json", "body": responseData.base64EncodedString()]
    }
    private func enrolledKey(_ endpoint: URL) async throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService, kSecAttrAccount as String: "key-id", kSecReturnData as String: true]
        var stored: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &stored) == errSecSuccess, let data = stored as? Data, let key = String(data: data, encoding: .utf8) { return key }
        let key = try await DCAppAttestService.shared.generateKey()
        let challenge = try await post(endpoint.appendingPathComponent("challenge"), value: ["purpose": "attest", "keyId": key])
        guard let id = challenge["id"] as? String, let nonce = challenge["challenge"] as? String else { throw LocalRecipeError.invalid("No se pudo verificar la instalación.") }
        let attestation = try await DCAppAttestService.shared.attestKey(key, clientDataHash: Data(SHA256.hash(data: Data(nonce.utf8))))
        _ = try await post(endpoint.appendingPathComponent("attest"), value: ["keyId": key, "challengeId": id, "attestation": attestation.base64EncodedString()])
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService, kSecAttrAccount as String: "key-id", kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData as String: Data(key.utf8)]
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw LocalRecipeError.invalid("No se pudo guardar la verificación del dispositivo.") }
        return key
    }
    private func post(_ url: URL, value: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: value)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 64_000, (200..<300).contains(http.statusCode), let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LocalRecipeError.invalid("No se pudo verificar la conexión de IA. No se ha enviado una petición de generación.") }
        return result
    }
}

private final class RejectAIRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
