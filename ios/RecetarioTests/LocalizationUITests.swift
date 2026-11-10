import XCTest
import UIKit
import WebKit
@testable import Recetario

@MainActor final class LocalizationUITests: XCTestCase {
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
                let result=try await web.callAsyncJavaScript("return await "+script,arguments:["language":language,"stage":"full"],in:nil,contentWorld:.page) as? [String:Any]
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
