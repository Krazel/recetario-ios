import XCTest
import UIKit
@testable import Recetario

@MainActor final class LocalRecipeBackupTests: XCTestCase {
    private func fixture() throws -> (URL, LocalRecipeStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (directory, try LocalRecipeStore(file: directory.appendingPathComponent("recipes.json")))
    }
    private func photo() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return try XCTUnwrap(renderer.image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }.jpegData(compressionQuality: 0.7))
    }
    func testLocalModeKeepsLegacyCacheWithoutResumingSync() throws {
        let (directory, _) = try fixture()
        let file = directory.appendingPathComponent("legacy.json")
        var legacy = LocalState()
        legacy.active = "old-account"
        var old = LocalRecipe(id: "old-recipe", title: "Guardada antes")
        old.operationId = "pending-from-old-version"
        legacy.accounts[legacy.active] = LocalAccount(email: "fixture@example.test", records: [old.id: old])
        try JSONEncoder().encode(legacy).write(to: file)
        let store = try LocalRecipeStore(file: file)
        XCTAssertEqual(store.visible.count, 1)
        XCTAssertThrowsError(try store.batch())
        XCTAssertThrowsError(try store.link(accountId: "other-account", email: "other@example.test", remote: []))
        var edited = try XCTUnwrap(store.visible.first); edited.title = "Edición local"
        try store.save(edited)
        XCTAssertNil(store.visible.first?.operationId)
        XCTAssertEqual(try LocalRecipeStore(file: file).visible.first?.title, "Edición local")
    }
    func testBackupRoundTripIncludesPhotoAndDeduplicates() throws {
        let (_, source) = try fixture(), (_, destination) = try fixture()
        let bytes = try photo(), photoID = try source.savePhoto(bytes)
        var recipe = LocalRecipe(id: UUID().uuidString.lowercased(), title: "Con foto", ingredients: "250 g de arroz", steps: "Cocer", notes: "Para dos")
        recipe.photoID = photoID; recipe.collection = "Cenas"; recipe.favorite = true
        recipe.sourceURL = "https://example.test/recipe"
        try source.save(recipe)
        let data = try source.makeBackup(), preview = try destination.previewBackup(data)
        XCTAssertEqual(preview.count, 1)
        XCTAssertEqual(try destination.restore(preview), 1)
        XCTAssertEqual(try destination.photoData(photoID), bytes)
        XCTAssertTrue(try XCTUnwrap(destination.visible.first).matches(recipe))
        XCTAssertNil(destination.visible.first?.operationId)
        XCTAssertEqual(try destination.restore(try destination.previewBackup(data)), 0)
    }
    func testIDCollisionPreservesExistingRecipe() throws {
        let (_, store) = try fixture()
        try store.save(LocalRecipe(id: "same-id", title: "Original"))
        let copy = LocalRecipeBackup(recipes: [LocalRecipe(id: "same-id", title: "Otra receta")], photos: [:])
        XCTAssertEqual(try store.restore(try store.previewBackup(JSONEncoder().encode(copy))), 1)
        XCTAssertEqual(store.records["same-id"]?.title, "Original")
        XCTAssertEqual(Set(store.visible.map(\.title)), Set(["Original", "Otra receta"]))
    }
    func testTamperedOrMissingPhotosNeverChangeRecipes() throws {
        let (_, store) = try fixture()
        try store.save(LocalRecipe(id: "existing", title: "Conservar"))
        let original = try Data(contentsOf: store.file)
        let bytes = try photo(), id = LocalRecipeStore.photoID(bytes)
        var recipe = LocalRecipe(id: "imported", title: "No importar"); recipe.photoID = id
        for photos in [[:], [id: Data("damaged".utf8)]] as [[String: Data]] {
            let backup = LocalRecipeBackup(recipes: [recipe], photos: photos)
            XCTAssertThrowsError(try store.previewBackup(JSONEncoder().encode(backup)))
            XCTAssertEqual(try Data(contentsOf: store.file), original)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.mediaDirectory.path))
    }
    func testPhotoPathTraversalAndDuplicateRecipeIDsAreRejected() throws {
        let (_, store) = try fixture()
        var recipe = LocalRecipe(id: "one", title: "No importar"); recipe.photoID = "../private.jpg"
        XCTAssertThrowsError(try store.previewBackup(JSONEncoder().encode(LocalRecipeBackup(recipes: [recipe], photos: [:]))))
        recipe.photoID = nil
        XCTAssertThrowsError(try store.previewBackup(JSONEncoder().encode(LocalRecipeBackup(recipes: [recipe, recipe], photos: [:]))))
        XCTAssertThrowsError(try store.photoData("../private.jpg"))
        XCTAssertTrue(store.visible.isEmpty)
    }
    func testLegacyTextBackupAndFutureFormatHandling() throws {
        let (_, store) = try fixture()
        let old = Data("[{\"id\":\"legacy\",\"title\":\"Sin foto\",\"ingredients\":\"\",\"steps\":\"\",\"notes\":\"\",\"deleted\":false,\"revision\":0}]".utf8)
        XCTAssertEqual(try store.restore(try store.previewBackup(old)), 1)
        var future = LocalRecipeBackup(recipes: [], photos: [:]); future.version = 999
        XCTAssertThrowsError(try store.previewBackup(JSONEncoder().encode(future)))
        XCTAssertEqual(store.visible.first?.title, "Sin foto")
    }
    func testStaleEditorCannotOverwriteLocalChangeOrDeletion() throws {
        let (_, store) = try fixture()
        try store.save(LocalRecipe(id: "one", title: "Primera"))
        var stale = try XCTUnwrap(store.visible.first), current = stale
        current.favorite = true; try store.save(current)
        stale.title = "Borrador antiguo"
        XCTAssertThrowsError(try store.save(stale))
        try store.delete(try XCTUnwrap(store.records["one"]))
        XCTAssertThrowsError(try store.save(stale))
        XCTAssertTrue(store.visible.isEmpty)
    }
    func testFailedDiskWriteNeverClaimsSave() throws {
        let (directory, _) = try fixture()
        let store = try LocalRecipeStore(file: directory.appendingPathComponent("missing-parent/recipes.json"))
        XCTAssertThrowsError(try store.save(LocalRecipe(id: "one", title: "Sin guardar")))
        XCTAssertTrue(store.visible.isEmpty)
    }
    func testPhotoWriteFailureDoesNotAddRecipes() throws {
        let (directory, store) = try fixture()
        try store.save(LocalRecipe(id: "existing", title: "Conservar"))
        let bytes = try photo(), id = LocalRecipeStore.photoID(bytes)
        var recipe = LocalRecipe(id: "imported", title: "Nueva"); recipe.photoID = id
        let preview = try store.previewBackup(JSONEncoder().encode(LocalRecipeBackup(recipes: [recipe], photos: [id: bytes])))
        // A regular file at the media directory forces the write to fail.
        try Data("fixture".utf8).write(to: store.mediaDirectory)
        XCTAssertThrowsError(try store.restore(preview))
        XCTAssertEqual(store.visible.map(\.title), ["Conservar"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }
}
