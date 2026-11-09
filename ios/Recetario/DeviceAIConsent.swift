import Foundation

enum DeviceAIConsent {
    static let key = "recetario:ai-consent"
    private struct Record: Decodable { let version: String; let granted: Bool }
    static func granted(_ raw: String?) -> Bool {
        guard let raw, let data=raw.data(using:.utf8),
              let value=try? JSONDecoder().decode(Record.self,from:data),
              value.version == "openai-v1", value.granted else { return false }
        return true
    }
}
