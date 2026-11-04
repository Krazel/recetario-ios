import XCTest
@testable import Recetario

final class LocalRecipeStoreTests: XCTestCase {
    @MainActor func testGuestPersistsWithoutAccount() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:file) }
        let store=try LocalRecipeStore(file:file)
        try store.save(LocalRecipe(id:UUID().uuidString.lowercased(),title:"Sin cuenta"))
        let reopened=try LocalRecipeStore(file:file)
        XCTAssertEqual(reopened.state.active,"guest");XCTAssertEqual(reopened.visible.first?.title,"Sin cuenta")
        XCTAssertNil(reopened.visible.first?.operationId);XCTAssertThrowsError(try reopened.batch())
    }
    @MainActor func testMergeDeduplicatesAndLogoutSeparatesAccountCache() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json")
        defer { try? FileManager.default.removeItem(at:file) }
        let store=try LocalRecipeStore(file:file,cloudSyncEnabled:true),id=UUID().uuidString.lowercased(),uid=UUID().uuidString.lowercased()
        var remote=LocalRecipe(id:id,title:"Idéntica");remote.revision=1
        try store.save(LocalRecipe(id:UUID().uuidString.lowercased(),title:"Idéntica"))
        try store.save(LocalRecipe(id:UUID().uuidString.lowercased(),title:"Solo local"))
        try store.link(accountId:uid,email:"ana@example.test",remote:[remote])
        XCTAssertEqual(store.visible.count,2);XCTAssertEqual(store.records.values.filter{$0.operationId != nil}.count,1)
        try store.detach();XCTAssertTrue(store.visible.isEmpty);XCTAssertEqual(store.state.accounts[uid]?.records.count,2)
        try store.save(LocalRecipe(id:UUID().uuidString.lowercased(),title:"Otra cuenta"))
        try store.link(accountId:UUID().uuidString.lowercased(),email:"bruno@example.test",remote:[])
        XCTAssertEqual(store.visible.map{$0.title},["Otra cuenta"])
    }
    @MainActor func testCorruptFileIsNeverReplacedWithEmptyState() throws {
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".json"),bytes=Data("invalid fixture".utf8)
        defer { try? FileManager.default.removeItem(at:file) }
        try bytes.write(to:file);XCTAssertThrowsError(try LocalRecipeStore(file:file));XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
}
