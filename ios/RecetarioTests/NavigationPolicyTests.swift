import XCTest
@testable import Recetario
final class NavigationPolicyTests: XCTestCase {
    func testShortcutsAcceptPlainLinksAndSharedTextFromSeveralApps() {
        for raw in ["https://youtu.be/abc", "https://www.tiktok.com/@author/video/123", "https://www.instagram.com/reel/abc/", "Mira esta receta: https://www.bonviveur.es/recetas/arroz"] {
            var incoming = URLComponents(string: "krazel-recetario://import")!
            incoming.queryItems = [URLQueryItem(name: "url", value: raw)]
            XCTAssertNotNil(NavigationPolicy.importSourceURL(incoming.url!))
            if raw.hasPrefix("Mira") { XCTAssertEqual(NavigationPolicy.importSourceText(incoming.url!), raw) }
        }
        var invalid = URLComponents(string: "krazel-recetario://import")!
        invalid.queryItems = [URLQueryItem(name: "url", value: "Solo un texto sin enlace")]
        XCTAssertNil(NavigationPolicy.importSourceURL(invalid.url!))
        invalid.queryItems = [URLQueryItem(name: "url", value: "https://user:password@example.com")]
        XCTAssertNil(NavigationPolicy.importSourceURL(invalid.url!))
    }
    func testTrustedOrigin() {
        XCTAssertTrue(NavigationPolicy.isTrusted(URL(string: "https://recetario-krazel.krazel.chatgpt.site/importar")))
        for raw in ["http://recetario-krazel.krazel.chatgpt.site", "https://recetario-krazel.krazel.chatgpt.site.evil.test", "https://user:pass@recetario-krazel.krazel.chatgpt.site", "https://recetario-krazel.krazel.chatgpt.site:8000"] { XCTAssertFalse(NavigationPolicy.isTrusted(URL(string: raw))) }
    }
    func testSharedLinkIsEncodedAndNeverExecuted() {
        let good = URL(string: "krazel-recetario://import?url=https%3A%2F%2Fwww.instagram.com%2Freel%2Fabc%2F")!
        XCTAssertEqual(NavigationPolicy.importURL(good)?.host, NavigationPolicy.origin.host)
        XCTAssertEqual(NavigationPolicy.importSourceURL(good)?.host, "www.instagram.com")
        XCTAssertNil(NavigationPolicy.importSourceURL(URL(string: "krazel-recetario://import?url=file%3A%2F%2F%2Fprivate%2Fsecret")!))
        XCTAssertNil(NavigationPolicy.importURL(URL(string: "krazel-recetario://import?url=javascript%3Aalert(1)")!))
    }
    func testVideoFramesDoNotBecomeTrustedMainDocuments() {
        let video = URL(string: "https://www.youtube-nocookie.com/embed/abc")!
        XCTAssertTrue(NavigationPolicy.isVideoEmbed(video))
        XCTAssertFalse(NavigationPolicy.isTrusted(video))
        XCTAssertFalse(NavigationPolicy.isVideoEmbed(URL(string: "https://www.youtube.com.evil.test/embed/abc")!))
    }
    func testNativeMessagesRequireKnownSectionsAndBooleans() {
        XCTAssertNotNil(NativeNavigationState(["action":"navigation","section":"planner","visible":true,"keepAwake":false]))
        XCTAssertNil(NativeNavigationState(["action":"navigation","section":"javascript:alert(1)","visible":true,"keepAwake":false]))
        XCTAssertNil(NativeNavigationState(["action":"navigation","section":"recipes","visible":"true"]))
        XCTAssertEqual(NativeSection.allCases.count, 4)
    }
}
