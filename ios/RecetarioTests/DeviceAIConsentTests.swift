import XCTest
@testable import Recetario

final class DeviceAIConsentTests: XCTestCase {
    func testOnlyCurrentExplicitPermissionEnablesAI() {
        XCTAssertFalse(DeviceAIConsent.granted(nil))
        XCTAssertFalse(DeviceAIConsent.granted("invalid"))
        XCTAssertFalse(DeviceAIConsent.granted("{\"version\":\"old\",\"granted\":true}"))
        XCTAssertFalse(DeviceAIConsent.granted("{\"version\":\"openai-v1\",\"granted\":false}"))
        XCTAssertFalse(DeviceAIConsent.granted("{\"version\":\"openai-v1\",\"granted\":1}"))
        XCTAssertTrue(DeviceAIConsent.granted("{\"version\":\"openai-v1\",\"granted\":true}"))
    }
}
