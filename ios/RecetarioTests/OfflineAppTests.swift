import XCTest
import UIKit
import WebKit
@testable import Recetario

@MainActor final class OfflineAppTests: XCTestCase {
    func testSharedDescriptionSurvivesColdStartAndQueuedWarmImport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let controller = try OfflineAppController(database: DeviceDatabase(file: folder.appendingPathComponent("shared.sqlite")))
        let caption = "Ingredientes:\n2 huevos\nPreparación:\nBatir."
        controller.openImportSource(URL(string: "https://youtu.be/cold-start")!, text: caption)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.loadViewIfNeeded()
        defer { window.isHidden = true; try? FileManager.default.removeItem(at: folder) }
        let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
        for _ in 0..<240 {
            if (try? await web.evaluateJavaScript("window.__recetarioImportReady === 1")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        let checkCold = """
        for(let i=0;i<200;i++){if(document.querySelector('.import-panel textarea[aria-label="Descripción de la publicación"]'))break;await new Promise(r=>setTimeout(r,25));}
        return {text:document.querySelector('.import-panel textarea')?.value,url:document.querySelector('.import-panel input[type=url]')?.value};
        """
        let cold = try await web.callAsyncJavaScript(checkCold, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(cold?["text"] as? String, caption)
        XCTAssertEqual(cold?["url"] as? String, "https://youtu.be/cold-start")
        controller.openImportSource(URL(string: "https://www.tiktok.com/@author/video/123")!, text: "Descripción compartida de prueba")
        let checkWarm = """
        for(let i=0;i<200;i++){if([...document.querySelectorAll('button')].some(b=>b.textContent==='Abrir siguiente enlace'))break;await new Promise(r=>setTimeout(r,25));}
        if(document.querySelector('.import-panel textarea')?.value!==caption)throw Error('La recepción cambió el formulario abierto');
        document.querySelector('.import-heading button').click();await new Promise(r=>setTimeout(r,100));
        [...document.querySelectorAll('button')].find(b=>b.textContent==='Abrir siguiente enlace').click();await new Promise(r=>setTimeout(r,100));
        return {text:document.querySelector('.import-panel textarea')?.value,url:document.querySelector('.import-panel input[type=url]')?.value};
        """
        let warm = try await web.callAsyncJavaScript(checkWarm, arguments: ["caption":caption], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(warm?["text"] as? String, "Descripción compartida de prueba")
        XCTAssertEqual(warm?["url"] as? String, "https://www.tiktok.com/@author/video/123")
    }
    func testCorrectionFlowsAndLayoutInRealWebView() async throws {
        for size in [CGSize(width: 320, height: 740), CGSize(width: 390, height: 400), CGSize(width: 430, height: 900)] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let database = try DeviceDatabase(file: folder.appendingPathComponent("corrections.sqlite"))
            let controller = try OfflineAppController(database: database)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller; window.makeKeyAndVisible()
            controller.loadViewIfNeeded(); controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            defer { window.isHidden = true; try? FileManager.default.removeItem(at: folder) }
            let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
            for _ in 0..<240 {
                if (try? await web.evaluateJavaScript("typeof window.__recetarioExport === 'function'")) as? Bool == true { break }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CorrectionFlow", withExtension: "js"))
            let script = "return await " + (try String(contentsOf: file, encoding: .utf8))
            let result = try await web.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
            print("RECETARIO_CORRECTION_UI=\(result ?? [:])")
            XCTAssertEqual(result?["editor"] as? String, "contained")
            XCTAssertEqual(result?["preferences"] as? String, "closed on save")
            XCTAssertEqual(result?["width"] as? Int, Int(size.width))
        }
    }
    func testBundledAppStartsAndPersistsARecipeThroughTheNativeBridge() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let database = try DeviceDatabase(file: folder.appendingPathComponent("app.sqlite"))
        let controller = try OfflineAppController(database: database)
        // The app uses AppDelegate windows rather than a scene manifest.
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.loadViewIfNeeded()
        let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
        var ready = false
        for _ in 0..<240 {
            ready = (try? await web.evaluateJavaScript("typeof window.__recetarioExport === 'function' && document.querySelector('button') !== null")) as? Bool == true
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
