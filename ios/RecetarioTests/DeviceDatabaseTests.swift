import XCTest
@testable import Recetario

final class DeviceDatabaseTests: XCTestCase {
    private let migration = "CREATE TABLE notes(id TEXT PRIMARY KEY, value TEXT NOT NULL);"
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("device.sqlite")
    }
    func testBoundTextSurvivesReopenIncludingUnicodeAndNull() async throws {
        let path = try file(), value = "Tortilla 🍳\u{0}con tomate"
        var database: DeviceDatabase? = try DeviceDatabase(file: path, migrations: [migration])
        _ = try await database!.execute([["sql": "INSERT INTO notes VALUES(?,?)", "values": ["one", value]]])
        database = nil
        let reopened = try DeviceDatabase(file: path, migrations: [migration])
        let result = try await reopened.execute([["sql": "SELECT value FROM notes WHERE id=?", "values": ["one"]]])
        XCTAssertEqual((result[0]["results"] as? [[String: Any]])?.first?["value"] as? String, value)
    }
    func testBatchRollsBackEveryChangeWhenAnyStatementFails() async throws {
        let database = try DeviceDatabase(file: file(), migrations: [migration])
        do {
            _ = try await database.execute([
                ["sql": "INSERT INTO notes VALUES(?,?)", "values": ["one", "Conservar"]],
                ["sql": "INSERT INTO nonexistent VALUES(?)", "values": ["fail"]]
            ])
            XCTFail("An invalid statement must fail the entire batch")
        } catch {}
        let result = try await database.execute([["sql": "SELECT COUNT(*) AS count FROM notes", "values": []]])
        XCTAssertEqual((result[0]["results"] as? [[String: Any]])?.first?["count"] as? Int, 0)
    }
    func testMigrationCannotBeSilentlyRewritten() throws {
        let path = try file()
        var first: DeviceDatabase? = try DeviceDatabase(file: path, migrations: [migration]); XCTAssertNotNil(first); first = nil
        XCTAssertThrowsError(try DeviceDatabase(file: path, migrations: [migration + "CREATE TABLE unexpected(id TEXT);"]))
        XCTAssertNoThrow(try DeviceDatabase(file: path, migrations: [migration]))
    }
    func testDraftKeysPersistAndCanBeRemoved() async throws {
        let path = try file(), database = try DeviceDatabase(file: path, migrations: [migration])
        try await database.writeKey("recetario:timers:one", value: "{\"deadline\":123}")
        let values = try await database.keyValues()
        XCTAssertEqual(values["recetario:timers:one"], "{\"deadline\":123}")
        try await database.writeKey("recetario:timers:one", value: nil)
        let removed = try await database.keyValues(); XCTAssertNil(removed["recetario:timers:one"])
    }
    @MainActor func testBundledAppContainsEntryAndMigrations() throws {
        let directory = try XCTUnwrap(Bundle.main.url(forResource: "OfflineApp", withExtension: nil))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("mobile/index.html").path))
        let scripts = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("migrations.json")))
        XCTAssertEqual(scripts.count, 15)
        XCTAssertTrue(scripts.last?.contains("ADD `language` text") == true)
    }
}
