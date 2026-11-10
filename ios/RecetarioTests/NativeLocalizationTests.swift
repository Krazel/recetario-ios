import XCTest
@testable import Recetario

final class NativeLocalizationTests: XCTestCase {
    func testSystemFallbackAndExplicitPreference() {
        XCTAssertEqual(NativeLocalization.languages, ["en","es","ca","de","fr","it","pt"])
        XCTAssertEqual(NativeLocalization.effective("system", preferred: ["ja-JP","ca-ES"]), "ca")
        XCTAssertEqual(NativeLocalization.effective(nil, preferred: ["ko-KR"]), "en")
        XCTAssertEqual(NativeLocalization.effective("fr", preferred: ["de-DE"]), "fr")
        XCTAssertEqual(NativeLocalization.effective("invalid", preferred: ["pt_BR"]), "pt")
    }
    func testNativeResourcesAndSpeechLocalesExistForAllSeven() {
        for language in NativeLocalization.languages {
            XCTAssertNotNil(Bundle.main.path(forResource: language, ofType: "lproj"), language)
            let result=NativeLocalization.text("Importar {count} recetas", language: language, values: ["count":"7"])
            XCTAssertTrue(result.contains("7"), result)
            XCTAssertFalse(result.contains("{count}"), result)
            if language != "es" { XCTAssertNotEqual(result,"Importar 7 recetas",language) }
            XCTAssertTrue(NativeLocalization.voiceLocale(language).hasPrefix(language+"-"))
        }
    }
}
