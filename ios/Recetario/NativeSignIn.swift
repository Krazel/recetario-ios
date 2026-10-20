import Foundation
import CryptoKit
import Security

struct NativeSignIn {
    let verifier: String
    let state: String
    init() throws { verifier = try Self.random(); state = try Self.random() }
    init(verifier: String, state: String) { self.verifier = verifier; self.state = state }
    var challenge: String { Self.encode(Data(SHA256.hash(data: Data(verifier.utf8)))) }
    var displayCode: String { String(state.prefix(6)).uppercased() }
    var authorizationURL: URL {
        var url = URLComponents(url: NavigationPolicy.signInOrigin.appendingPathComponent("ios/connect"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "challenge", value: challenge), URLQueryItem(name: "state", value: state)]
        return url.url!
    }
    func exchangeRequest(callback: URL) -> URLRequest? {
        guard callback.scheme == "krazel-recetario", callback.host == "session", callback.path.isEmpty,
              callback.user == nil, callback.password == nil, callback.port == nil, callback.fragment == nil,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 2, items.filter({ $0.name == "state" }).count == 1, items.filter({ $0.name == "code" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value, Self.validProof(code) else { return nil }
        var request = URLRequest(url: NavigationPolicy.origin.appendingPathComponent("native/session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(NavigationPolicy.origin.absoluteString, forHTTPHeaderField: "Origin")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "verifier": verifier])
        return request
    }
    static func validProof(_ value: String) -> Bool { value.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SignInError.random }
        return encode(Data(bytes))
    }
    private static func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    enum SignInError: Error { case random }
}
