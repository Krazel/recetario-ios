import XCTest
@testable import Recetario
final class NavigationPolicyTests: XCTestCase {
    func testTrustedOrigin() {
        XCTAssertTrue(NavigationPolicy.isTrusted(NavigationPolicy.origin.appendingPathComponent("importar")))
        XCTAssertFalse(NavigationPolicy.isTrusted(NavigationPolicy.signInOrigin))
        for raw in ["http://recetario-krazel.krazel.chatgpt.site", "https://recetario-krazel.krazel.chatgpt.site.evil.test", "https://user:pass@recetario-krazel.krazel.chatgpt.site", "https://recetario-krazel.krazel.chatgpt.site:8000"] { XCTAssertFalse(NavigationPolicy.isTrusted(URL(string: raw))) }
    }
    func testPKCEAndCallbackBinding() {
        // RFC 7636 test vector.
        let attempt = NativeSignIn(verifier:"dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",state:String(repeating:"s",count:43))
        XCTAssertEqual(attempt.challenge,"E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(attempt.authorizationURL.host,NavigationPolicy.signInOrigin.host)
        let code=String(repeating:"c",count:43), state=attempt.state
        let request=attempt.exchangeRequest(callback:URL(string:"krazel-recetario://session?code=\(code)&state=\(state)")!)
        XCTAssertEqual(request?.url?.path,"/native/session")
        XCTAssertEqual(request?.httpMethod,"POST")
        XCTAssertFalse(request?.url?.absoluteString.contains(code) ?? true)
        for raw in ["krazel-recetario://session?code=\(code)&state=wrong", "krazel-recetario://session?code=\(code)&state=\(state)&state=\(state)", "https://session?code=\(code)&state=\(state)", "krazel-recetario://session/extra?code=\(code)&state=\(state)","krazel-recetario://session?code=short&state=\(state)"] {
            XCTAssertNil(attempt.exchangeRequest(callback:URL(string:raw)!))
        }
    }
    func testSignInUsesFreshRandomProofs() throws {
        let a=try NativeSignIn(), b=try NativeSignIn()
        XCTAssertTrue(NativeSignIn.validProof(a.verifier)); XCTAssertTrue(NativeSignIn.validProof(a.state))
        XCTAssertNotEqual(a.verifier,b.verifier); XCTAssertNotEqual(a.state,b.state)
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
