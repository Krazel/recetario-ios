import Foundation

enum NativeLocalization {
    static let languages = ["en", "es", "ca", "de", "fr", "it", "pt"]
    static let preferenceKey = "recetario:language"
    static func voiceLocale(_ language: String) -> String { ["en":"en-GB", "es":"es-ES", "ca":"ca-ES", "de":"de-DE", "fr":"fr-FR", "it":"it-IT", "pt":"pt-PT"][language] ?? "en-GB" }
    static func effective(_ preference: String?, preferred: [String] = Locale.preferredLanguages) -> String {
        if let preference, languages.contains(preference) { return preference }
        for locale in preferred {
            let base = locale.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first.map(String.init) ?? ""
            if languages.contains(base) { return base }
        }
        return "en"
    }
    static func text(_ source: String, language: String, values: [String: String] = [:]) -> String {
        let code = languages.contains(language) ? language : "en"
        let selected = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        let english = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        var result = selected?.localizedString(forKey: source, value: english?.localizedString(forKey: source, value: source, table: nil) ?? source, table: nil) ?? source
        for (key, value) in values { result = result.replacingOccurrences(of: "{" + key + "}", with: value) }
        return result
    }
}
