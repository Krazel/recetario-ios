import Foundation

enum NavigationPolicy {
    static let origin = URL(string: "https://recetario-krazel.krazel.chatgpt.site")!
    static func isTrusted(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == origin.host && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
    static func importURL(_ url: URL) -> URL? {
        guard url.scheme == "krazel-recetario", url.host == "import",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: {$0.name == "url"})?.value, raw.count <= 2048,
              let source = URL(string: raw), ["https", "http"].contains(source.scheme ?? ""), source.host != nil,
              source.user == nil, source.password == nil else { return nil }
        var target = URLComponents(url: origin.appendingPathComponent("importar"), resolvingAgainstBaseURL: false)!
        target.queryItems = [URLQueryItem(name: "url", value: raw)]
        return target.url
    }
    static func isVideoEmbed(_ url: URL) -> Bool {
        let hosts = ["www.youtube.com", "www.youtube-nocookie.com", "www.instagram.com", "www.tiktok.com", "player.vimeo.com"]
        return url.scheme == "https" && hosts.contains(url.host ?? "") && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
}
