import Foundation

enum DeviceAIConsent {
    static let key = "recetario:ai-consent"
    private struct Record: Decodable {
        enum CodingKeys: String, CodingKey { case version, granted, scopes }
        let version: String
        let granted: Bool
        let scopes: [String]?
        init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            version = try fields.decode(String.self, forKey: .version)
            granted = try fields.decode(Bool.self, forKey: .granted)
            scopes = fields.contains(.scopes) ? (try fields.decodeIfPresent([String].self, forKey: .scopes) ?? []) : nil
        }
    }
    static func scope(for path: String) -> String? {
        switch path {
        case "/api/import", "/api/recipe-media": return "recipes"
        case "/api/assistant", "/api/assistant/image": return "assistant"
        default: return nil
        }
    }
    static func granted(_ raw: String?, scope: String? = nil) -> Bool {
        guard let raw, let data=raw.data(using:.utf8),
              let value=try? JSONDecoder().decode(Record.self,from:data),
              value.version == "openai-v1", value.granted else { return false }
        guard let scopes = value.scopes else { return true }
        guard scopes.allSatisfy({ $0 == "recipes" || $0 == "assistant" }) else { return false }
        if let scope { return scopes.contains(scope) }
        return scopes.contains("recipes") || scopes.contains("assistant")
    }
}
