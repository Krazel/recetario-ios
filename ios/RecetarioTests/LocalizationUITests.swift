import XCTest
import UIKit
import WebKit
@testable import Recetario

@MainActor final class LocalizationUITests: XCTestCase {
    func testSharedHeaderAlignmentAcrossTabs() async throws {
        let resource = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CookingEditorialFlow", withExtension: "js"))
        let script = try String(contentsOf: resource, encoding: .utf8)
        for width in [320, 390, 430, 1100] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let database = try DeviceDatabase(file: folder.appendingPathComponent("header.sqlite"))
            let controller = try OfflineAppController(database: database)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: CGFloat(width), height: 740))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.loadViewIfNeeded()
            controller.view.frame = window.bounds
            controller.view.layoutIfNeeded()
            defer { window.isHidden = true }
            let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
            for _ in 0..<240 {
                if (try? await web.evaluateJavaScript("!!window.__recetarioLanguage && !!document.querySelector('.library-toolbar')")) as? Bool == true { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            let result = try await web.callAsyncJavaScript("return await " + script, arguments: ["stage": "header"], in: nil, contentWorld: .page)
            let metrics = try XCTUnwrap(result as? [String: Any])
            XCTAssertEqual(metrics["viewport"] as? Int, width)
            print("RECETARIO_HEADER_QA=\(width):\(metrics)")
            if width == 390 { try await snapshot(web, name: "recisave-header-390") }
        }
    }

    func testEditorialCookingKeepsControlsAndRecipeAtPhoneAndTabletWidths() async throws {
        let resource = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "CookingEditorialFlow", withExtension: "js"))
        let script = try String(contentsOf: resource, encoding: .utf8)
        let bundle = try XCTUnwrap(Bundle.main.url(forResource: "OfflineApp", withExtension: nil))
        let image = try XCTUnwrap(UIImage(contentsOfFile: bundle.appendingPathComponent("images/tomato-pasta.jpg").path))
        let size = CGSize(width: 220, height: 220 * image.size.height / image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let fixture = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.55) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        let photoDataURL = "data:image/jpeg;base64," + fixture.base64EncodedString()
        XCTAssertLessThan(photoDataURL.count, 40_000)
        for size in [CGSize(width: 320, height: 740), CGSize(width: 390, height: 844), CGSize(width: 820, height: 1080)] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let database = try DeviceDatabase(file: folder.appendingPathComponent("cooking.sqlite"))
            let controller = try OfflineAppController(database: database)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(origin: .zero, size: size)
            controller.view.layoutIfNeeded()
            defer { window.isHidden = true }
            let web = try XCTUnwrap(controller.view.subviews.compactMap { $0 as? WKWebView }.first)
            for _ in 0..<240 {
                if (try? await web.evaluateJavaScript("!!window.__recetarioLanguage && !!document.querySelector('.library-toolbar')")) as? Bool == true { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            for stage in ["prepare", "controls", "languages"] {
                var arguments = ["stage": stage]
                if stage == "prepare" { arguments["photoDataURL"] = photoDataURL }
                let value = try await web.callAsyncJavaScript("return await " + script, arguments: arguments, in: nil, contentWorld: .page)
                let result = try XCTUnwrap(value as? [String: Any])
                XCTAssertEqual(result["width"] as? Int, Int(size.width))
                XCTAssertTrue((result["instructionFont"] as? String)?.contains("Georgia") == true)
                print("RECETARIO_COOKING_QA=\(stage):\(result)")
                if stage != "languages" {
                    try await snapshot(web, name: "cooking-a-\(stage)-\(Int(size.width))")
                }
            }
            if size.width == 390 {
                try await checkNativeKeyboardFrame(web, in: window)
                for stage in ["grid", "shopping", "profile"] {
                    let result = try await web.callAsyncJavaScript("return await " + script, arguments: ["stage": stage], in: nil, contentWorld: .page)
                    print("RECETARIO_SURFACE_QA=\(stage):\(String(describing: result))")
                    try await snapshot(web, name: "recisave-\(stage)-390")
                }
            }
        }
    }

    private func checkNativeKeyboardFrame(_ web: WKWebView, in window: UIWindow) async throws {
        let height = web.bounds.height
        let frame = web.convert(web.bounds, to: window.screen.coordinateSpace)
        let shown = CGRect(x: frame.minX, y: frame.maxY - 260, width: frame.width, height: 300)
        let hidden = CGRect(x: frame.minX, y: frame.maxY + 40, width: frame.width, height: 300)
        func post(_ name: Notification.Name, frame: CGRect) {
            NotificationCenter.default.post(name: name, object: nil, userInfo: [
                UIResponder.keyboardFrameEndUserInfoKey: NSValue(cgRect: frame),
                UIResponder.keyboardIsLocalUserInfoKey: true
            ])
        }
        func waitForBar(hidden: Bool) async throws {
            let condition = """
            window.__recetarioIOSViewport?.height === \(Double(height)) &&
            window.__recetarioIOSViewport?.keyboardVisible === \(hidden) &&
            document.documentElement.classList.contains('keyboard-open') === \(hidden)
            """
            for _ in 0..<100 {
                if try await web.evaluateJavaScript(condition) as? Bool == true { return }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("Keyboard visibility did not reach the web view: hidden=\(hidden)")
        }
        post(UIResponder.keyboardWillChangeFrameNotification, frame: shown)
        try await waitForBar(hidden: true)
        post(UIResponder.keyboardWillChangeFrameNotification, frame: hidden)
        try await waitForBar(hidden: true)
        post(UIResponder.keyboardDidChangeFrameNotification, frame: hidden)
        try await waitForBar(hidden: false)
        XCTAssertEqual(web.bounds.height, height)
        print("RECETARIO_KEYBOARD_FRAME_QA=\(height):native notifications verified")
    }

    private func snapshot(_ web: WKWebView, name: String) async throws {
        let config=WKSnapshotConfiguration();config.afterScreenUpdates=true
        let image:UIImage=try await withCheckedThrowingContinuation { continuation in web.takeSnapshot(with: config) { image,error in if let image { continuation.resume(returning:image) } else { continuation.resume(throwing:error ?? NSError(domain:"LocaleSnapshot",code:1)) } } }
        let data=try XCTUnwrap(image.pngData()).base64EncodedString()
        print("RECETARIO_QA_PNG_BEGIN=\(name):\(data.count)")
        for offset in stride(from:0,to:data.count,by:4096){let start=data.index(data.startIndex,offsetBy:offset),end=data.index(start,offsetBy:min(4096,data.count-offset));print("RECETARIO_QA_PNG_CHUNK=\(name):\(offset/4096):\(data[start..<end])")}
        print("RECETARIO_QA_PNG_END=\(name)")
    }
    func testSevenLanguageSettingsRecipeOverrideAndPreservationAtThreeWidths() async throws {
        let script=try String(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource:"LocalizationFlow",withExtension:"js")),encoding:.utf8)
        for size in [CGSize(width:320,height:740),CGSize(width:390,height:740),CGSize(width:430,height:900)] {
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let database=try DeviceDatabase(file:folder.appendingPathComponent("languages.sqlite"))
            let controller=try OfflineAppController(database:database)
            let window=UIWindow(frame:CGRect(origin:.zero,size:size));window.rootViewController=controller;window.makeKeyAndVisible();controller.loadViewIfNeeded();controller.view.frame=CGRect(origin:.zero,size:size);controller.view.setNeedsLayout();controller.view.layoutIfNeeded()
            defer { window.isHidden=true }
            let web=try XCTUnwrap(controller.view.subviews.compactMap{$0 as? WKWebView}.first)
            for _ in 0..<240 { if (try? await web.evaluateJavaScript("typeof window.__recetarioLanguage === 'object' && !!document.querySelector('.library-toolbar')")) as? Bool == true { break };try await Task.sleep(nanoseconds:100_000_000) }
            let initial=try await web.evaluateJavaScript("window.__recetarioLanguage.get()") as? String
            XCTAssertEqual(initial,NativeLocalization.effective(nil))
            for language in NativeLocalization.languages {
                let labels=["recipes":NativeLocalization.text("Recetas",language:language),"profile":NativeLocalization.text("Perfil",language:language),"addBreakfast":NativeLocalization.text("Añadir {p0}",language:language,values:["p0":NativeLocalization.text("Desayuno",language:language)]),"menuSettings":NativeLocalization.text("Ajustes del menú",language:language),"dairy":NativeLocalization.text("Lácteos y huevos",language:language)]
                let result=try await web.callAsyncJavaScript("return await "+script,arguments:["language":language,"stage":"full","labels":labels],in:nil,contentWorld:.page) as? [String:Any]
                XCTAssertEqual(result?["language"] as? String,language);XCTAssertEqual(result?["manualPreserved"] as? Bool,true)
                print("RECETARIO_LANGUAGE_UI=\(result ?? [:])")
                if size.width==320 {
                    try await snapshot(web,name:"locale-\(language)-profile-320")
                    _ = try await web.callAsyncJavaScript("return await "+script,arguments:["language":language,"stage":"home"],in:nil,contentWorld:.page)
                    try await snapshot(web,name:"locale-\(language)-home-320")
                }
            }
            web.reload()
            for _ in 0..<240 { if (try? await web.evaluateJavaScript("window.__recetarioLanguage?.get() === 'pt' && !!document.querySelector('.library-toolbar')")) as? Bool == true { break };try await Task.sleep(nanoseconds:100_000_000) }
            let finalLanguage=(try? await web.evaluateJavaScript("window.__recetarioLanguage.get()")) as? String
            XCTAssertEqual(finalLanguage,"pt")
            let reopened=try DeviceDatabase(file:database.file),values=try await reopened.keyValues();XCTAssertEqual(values[NativeLocalization.preferenceKey],"pt")
        }
    }
}
