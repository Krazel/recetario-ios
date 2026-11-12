import XCTest
import UIKit
import WebKit
@testable import Recetario

@MainActor final class StoreScreenshotTests: XCTestCase {
    private var appWebView: WKWebView?
    private var currentLocale="en"
    private func capture(_ name: String) async throws {
        // A DOM update alone can precede WebKit's presented frame. Flush through
        // afterScreenUpdates before asking simctl for the actual device image.
        let web=try XCTUnwrap(appWebView),configuration=WKSnapshotConfiguration()
        configuration.afterScreenUpdates=true
        let _: UIImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with:configuration) { image,error in
                if let image { continuation.resume(returning:image) }
                else { continuation.resume(throwing:error ?? NSError(domain:"StoreCapture",code:3)) }
            }
        }
        try await Task.sleep(nanoseconds:700_000_000)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let request = documents.appendingPathComponent("recetario-store-request.json")
        let ack = documents.appendingPathComponent("recetario-store-ack.json")
        let data = try JSONSerialization.data(withJSONObject: ["name":name,"locale":currentLocale])
        try data.write(to: request, options: .atomic)
        for _ in 0..<1800 {
            if let bytes = try? Data(contentsOf: ack), let value = try? JSONSerialization.jsonObject(with: bytes) as? [String:Any], value["name"] as? String == name, value["locale"] as? String == currentLocale {
                guard value["ok"] as? Bool == true else { throw NSError(domain:"StoreCapture",code:1,userInfo:[NSLocalizedDescriptionKey:value["error"] as? String ?? "Capture failed"]) }
                print("RECETARIO_STORE_CAPTURED=\(name)"); return
            }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTFail("Host did not capture \(name)"); throw NSError(domain:"StoreCapture",code:2)
    }
    func testActualNativeScreensForStore() async throws {
        let bundle=Bundle(for:Self.self)
        let config=try JSONSerialization.jsonObject(with:Data(contentsOf:XCTUnwrap(bundle.url(forResource:"StoreLocale",withExtension:"json")))) as! [String:String]
        let chosen=try XCTUnwrap(config["locale"])
        let locales=chosen == "all" ? NativeLocalization.languages : [chosen]
        for locale in locales { try await captureLocale(locale) }
    }
    private func captureLocale(_ locale:String) async throws {
        currentLocale=locale
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let bundle=Bundle(for:Self.self)
        guard NativeLocalization.languages.contains(locale) else { throw NSError(domain:"StoreLocale",code:1) }
        let fixtures=try JSONSerialization.jsonObject(with:Data(contentsOf:XCTUnwrap(bundle.url(forResource:"LocalizedFixtures",withExtension:"json")))) as! [String:Any]
        let fixture=try XCTUnwrap(fixtures[locale])
        let database=try DeviceDatabase(file:folder.appendingPathComponent("store.sqlite"))
        try await database.writeKey(NativeLocalization.preferenceKey,value:locale)
        let controller = try OfflineAppController(database:database)
        let window = UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController=controller; window.makeKeyAndVisible(); controller.loadViewIfNeeded()
        defer { window.isHidden=true; window.rootViewController=nil }
        let web=try XCTUnwrap(controller.view.subviews.compactMap{$0 as? WKWebView}.first)
        appWebView=web
        for _ in 0..<240 {
            if (try? await web.evaluateJavaScript("window.__recetarioImportReady===1")) as? Bool == true { break }
            try await Task.sleep(nanoseconds:250_000_000)
        }
        let file=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"StoreFixture",withExtension:"js"))
        _ = try await web.callAsyncJavaScript("return await "+String(contentsOf:file,encoding:.utf8),arguments:["locale":locale,"fixture":fixture],in:nil,contentWorld:.page)
        try await capture("01-recetas")
        _ = try await web.callAsyncJavaScript("const card=[...document.querySelectorAll('.card-open')].find(e=>e.innerText.includes(window.__storeRecipeTitle));if(!card)throw Error('Recipe card missing');card.click();await window.__storeWait(()=>document.querySelector('.detail-body'));await new Promise(r=>setTimeout(r,700));return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("02-receta")
        _ = try await web.callAsyncJavaScript("await window.__storeTap(window.__storeLabels['Cocinar']);await new Promise(r=>setTimeout(r,500));return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("03-cocinar")
        _ = try await web.callAsyncJavaScript("await window.__storeTap(window.__storeLabels['Cerrar modo cocinar']);document.querySelector('.bottom-nav button:nth-child(2)').click();await window.__storeWait(()=>document.querySelector('.planner'));return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("04-menu")
        _ = try await web.callAsyncJavaScript("await document.querySelector('.bottom-nav button:nth-child(3)').click();await window.__storeWait(()=>document.querySelector('.cesta-page'));return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("05-compra")
        _ = try await web.callAsyncJavaScript("await document.querySelector('.bottom-nav button:last-child').click();await window.__storeTap(window.__storeLabels['Mi despensa']);return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("06-despensa")
        let shareGuide = """
        document.querySelector('.bottom-nav button:last-child').click();
        await window.__storeTap(window.__storeLabels['Compartir enlaces']);
        await window.__storeWait(() => document.querySelector('.share-guide-dialog .share-guide-steps'));
        return true;
        """
        _ = try await web.callAsyncJavaScript(shareGuide, arguments: [:], in: nil, contentWorld: .page)
        try await capture("07-redes")
    }
}
