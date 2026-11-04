import XCTest
import UIKit
import WebKit
@testable import Recetario

@MainActor final class OfflineAppTests: XCTestCase {
    func testBundledAppStartsAndPersistsARecipeThroughTheNativeBridge() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try DeviceDatabase(file: folder.appendingPathComponent("app.sqlite"))
        let controller = try OfflineAppController(database: database)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.loadViewIfNeeded()
        let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
        var ready = false
        for _ in 0..<240 {
            ready = (try? await web.evaluateJavaScript("typeof window.__recetarioExport === 'function' && document.body.innerText.includes('Recetario')")) as? Bool == true
            if ready { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        let visible = (try? await web.evaluateJavaScript("document.body.innerText")) as? String ?? "No document"
        XCTAssertTrue(ready, visible)
        guard ready else { return }
        XCTAssertFalse(visible.contains("No se pudo abrir Recetario"), visible)
        let script = """
        const post = async body => {const response=await fetch('/api/recetario',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)}); const data=await response.json();if(!response.ok)throw Error(data.error);return data;};
        const {books}=await post({action:'bootstrap'});
        await post({action:'save',bookId:books[0].id,recipe:{title:'Prueba nativa 🍳',url:'',category:'Sin clasificar',ingredients:'2 tomates',steps:'Cortar los tomates.',notes:'',minutes:5,favorite:1,servings:2,tags:'',provenance:'Receta propia'}});
        const backup=await window.__recetarioExport();
        return {format:backup.format,title:backup.books[0].recipes[0].title};
        """
        let result = try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["format"] as? String, "recetario-device-v2")
        XCTAssertEqual(result?["title"] as? String, "Prueba nativa 🍳")
        let reopened = try DeviceDatabase(file: database.file)
        let rows = try await reopened.execute([["sql":"SELECT title,favorite FROM recipes", "values":[]]])
        let row = (rows.first?["results"] as? [[String: Any]])?.first
        XCTAssertEqual(row?["title"] as? String, "Prueba nativa 🍳")
        XCTAssertEqual(row?["favorite"] as? Int, 1)
    }
}
