import XCTest
import UIKit
import WebKit
@testable import Recetario

@MainActor final class StoreScreenshotTests: XCTestCase {
    private func capture(_ name: String) async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let request = documents.appendingPathComponent("recetario-store-request.json")
        let ack = documents.appendingPathComponent("recetario-store-ack.json")
        let data = try JSONSerialization.data(withJSONObject: ["name":name])
        try data.write(to: request, options: .atomic)
        for _ in 0..<1800 {
            if let bytes = try? Data(contentsOf: ack), let value = try? JSONSerialization.jsonObject(with: bytes) as? [String:Any], value["name"] as? String == name {
                guard value["ok"] as? Bool == true else { throw NSError(domain:"StoreCapture",code:1,userInfo:[NSLocalizedDescriptionKey:value["error"] as? String ?? "Capture failed"]) }
                print("RECETARIO_STORE_CAPTURED=\(name)"); return
            }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        XCTFail("Host did not capture \(name)"); throw NSError(domain:"StoreCapture",code:2)
    }
    func testActualNativeScreensForStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let controller = try OfflineAppController(database:DeviceDatabase(file:folder.appendingPathComponent("store.sqlite")))
        let window = UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController=controller; window.makeKeyAndVisible(); controller.loadViewIfNeeded()
        defer { window.isHidden=true; window.rootViewController=nil }
        let web=try XCTUnwrap(controller.view.subviews.compactMap{$0 as? WKWebView}.first)
        for _ in 0..<240 {
            if (try? await web.evaluateJavaScript("window.__recetarioImportReady===1")) as? Bool == true { break }
            try await Task.sleep(nanoseconds:250_000_000)
        }
        let file=try XCTUnwrap(Bundle(for:Self.self).url(forResource:"StoreFixture",withExtension:"js"))
        _ = try await web.callAsyncJavaScript("return await "+String(contentsOf:file,encoding:.utf8),arguments:[:],in:nil,contentWorld:.page)
        try await capture("01-recetas")
        _ = try await web.callAsyncJavaScript("const card=[...document.querySelectorAll('.card-open')].find(e=>e.innerText.includes('Pasta con tomate'));if(!card)throw Error('Recipe card missing');card.click();await window.__storeWait(()=>document.querySelector('.detail-body'));await new Promise(r=>setTimeout(r,700));return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("02-receta")
        _ = try await web.callAsyncJavaScript("await window.__storeTap('Cocinar');await new Promise(r=>setTimeout(r,500));return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("03-cocinar")
        _ = try await web.callAsyncJavaScript("await window.__storeTap('Cerrar modo cocinar');await window.__storeTap('Mi menú');return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("04-menu")
        _ = try await web.callAsyncJavaScript("await window.__storeTap('Compra');return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("05-compra")
        _ = try await web.callAsyncJavaScript("await window.__storeTap('Perfil');await window.__storeTap('Mi despensa');return true;",arguments:[:],in:nil,contentWorld:.page)
        try await capture("06-despensa")
    }
}
