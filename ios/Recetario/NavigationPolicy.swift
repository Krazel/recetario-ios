import Foundation

enum NavigationPolicy {
    static let origin = URL(string: "https://recetario-krazel.krazel.chatgpt.site")!
    static func isTrusted(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == origin.host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
    static func importSourceURL(_ url: URL) -> URL? {
        guard url.scheme == "krazel-recetario", url.host == "import",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: {$0.name == "url"})?.value, raw.count <= 30000,
              (items.first(where: {$0.name == "text"})?.value?.count ?? 0) <= 30000 else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let candidates = ([URL(string: trimmed)] + (detector?.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)).map { $0.url } ?? [])).compactMap { $0 }
        return candidates.first { source in
            source.absoluteString.count <= 2048 && ["https", "http"].contains(source.scheme ?? "") && source.host != nil && source.user == nil && source.password == nil
        }
    }
    static func importSourceText(_ url: URL) -> String {
        guard let source = importSourceURL(url), let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return "" }
        let explicit = items.first(where: {$0.name == "text"})?.value
        let raw = items.first(where: {$0.name == "url"})?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = explicit ?? (raw == source.absoluteString ? "" : raw)
        return text.count <= 30000 ? text : ""
    }
    static func importURL(_ url: URL) -> URL? {
        guard let source = importSourceURL(url) else { return nil }
        var target = URLComponents(url: origin.appendingPathComponent("importar"), resolvingAgainstBaseURL: false)!
        target.queryItems = [URLQueryItem(name: "url", value: source.absoluteString)]
        return target.url
    }
    static func isVideoEmbed(_ url: URL) -> Bool {
        let hosts = ["www.youtube.com", "www.youtube-nocookie.com", "www.instagram.com", "www.tiktok.com", "player.vimeo.com"]
        return url.scheme == "https" && hosts.contains(url.host ?? "") && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
}
