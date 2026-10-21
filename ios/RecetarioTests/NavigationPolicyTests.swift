import XCTest
@testable import Recetario
final class NavigationPolicyTests: XCTestCase {
    func testTrustedOrigin() {
        XCTAssertTrue(NavigationPolicy.isTrusted(URL(string: "https://recetario-krazel.krazel.chatgpt.site/importar")))
        for raw in ["http://recetario-krazel.krazel.chatgpt.site", "https://recetario-krazel.krazel.chatgpt.site.evil.test", "https://user:pass@recetario-krazel.krazel.chatgpt.site", "https://recetario-krazel.krazel.chatgpt.site:8000"] { XCTAssertFalse(NavigationPolicy.isTrusted(URL(string: raw))) }
    }
    func testSharedLinkIsEncodedAndNeverExecuted() {
        let good = URL(string: "krazel-recetario://import?url=https%3A%2F%2Fwww.instagram.com%2Freel%2Fabc%2F")!
        XCTAssertEqual(NavigationPolicy.importURL(good)?.host, NavigationPolicy.origin.host)
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
