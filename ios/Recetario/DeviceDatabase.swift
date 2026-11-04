import Foundation
import SQLite3
import CryptoKit

final class DeviceDatabase {
    private let queue = DispatchQueue(label: "com.krazel.recetario.database", qos: .userInitiated)
    private var database: OpaquePointer?
    let file: URL
    init(file: URL? = nil, migrations: [String]? = nil) throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.file = file ?? directory.appendingPathComponent("recetario-device.sqlite")
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: self.file.deletingLastPathComponent().path)
        let result = sqlite3_open_v2(self.file.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else { sqlite3_close(database); database = nil; throw LocalRecipeError.invalid("No se puede abrir el recetario local. Conserva la app y sus datos.") }
        do {
            sqlite3_busy_timeout(database, 5000)
            try sql("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: self.file.path)
            try sql("CREATE TABLE IF NOT EXISTS native_schema(version INTEGER PRIMARY KEY, sha TEXT NOT NULL); CREATE TABLE IF NOT EXISTS native_kv(key TEXT PRIMARY KEY, value TEXT NOT NULL);")
            let scripts: [String]
            if let migrations { scripts = migrations }
            else {
                guard let url = Bundle.main.url(forResource: "migrations", withExtension: "json", subdirectory: "OfflineApp") else { throw LocalRecipeError.invalid("La instalación no contiene la base local completa. Conserva tus datos y actualiza la app.") }
                scripts = try JSONDecoder().decode([String].self, from: Data(contentsOf: url))
            }
            for (version, script) in scripts.enumerated() {
                let hash = SHA256.hash(data: Data(script.utf8)).map { String(format: "%02x", $0) }.joined()
                let old = try statement("SELECT sha FROM native_schema WHERE version=?", values: [version])["results"] as? [[String: Any]] ?? []
                if let stored = old.first?["sha"] as? String {
                    guard stored == hash else { throw LocalRecipeError.invalid("La versión de los datos no coincide. Conserva la app y tu copia.") }
                    continue
                }
                try sql("BEGIN IMMEDIATE")
                do {
                    try sql(script)
                    _ = try statement("INSERT INTO native_schema(version,sha) VALUES(?,?)", values: [version, hash])
                    try sql("COMMIT")
                } catch { try? sql("ROLLBACK"); throw error }
            }
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { sqlite3_close(database) }
    private func sql(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw LocalRecipeError.invalid("No se pudo actualizar la base local. Conserva tu copia y vuelve a intentarlo.") }
    }
    private func statement(_ text: String, values: [Any]) throws -> [String: Any] {
        guard text.utf8.count <= 64_000, values.count <= 1000 else { throw LocalRecipeError.invalid("La operación local es demasiado grande.") }
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(database, text, -1, &prepared, nil) == SQLITE_OK, let prepared else { throw LocalRecipeError.invalid("No se ha podido preparar el guardado local.") }
        defer { sqlite3_finalize(prepared) }
        guard Int(sqlite3_bind_parameter_count(prepared)) == values.count else { throw LocalRecipeError.invalid("Faltan datos para guardar.") }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1), status: Int32
            if value is NSNull { status = sqlite3_bind_null(prepared, position) }
            else if let value = value as? String { status = value.withCString { sqlite3_bind_text(prepared, position, $0, Int32(value.utf8.count), transient) } }
            else if let number = value as? NSNumber {
                guard number.doubleValue.isFinite else { throw LocalRecipeError.invalid("Cantidad local no válida.") }
                if number.doubleValue.rounded() == number.doubleValue && abs(number.doubleValue) <= 9_007_199_254_740_991 { status = sqlite3_bind_int64(prepared, position, number.int64Value) }
                else { status = sqlite3_bind_double(prepared, position, number.doubleValue) }
            } else { throw LocalRecipeError.invalid("Formato de dato local no válido.") }
            guard status == SQLITE_OK else { throw LocalRecipeError.invalid("No se pudo preparar el dato local.") }
        }
        var rows: [[String: Any]] = [], bytes = 0
        while true {
            let status = sqlite3_step(prepared)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw LocalRecipeError.invalid("No se ha guardado el cambio. Revisa los datos y el espacio disponible.") }
            var row: [String: Any] = [:]
            for column in 0..<sqlite3_column_count(prepared) {
                let key = String(cString: sqlite3_column_name(prepared, column))
                switch sqlite3_column_type(prepared, column) {
                case SQLITE_INTEGER: row[key] = NSNumber(value: sqlite3_column_int64(prepared, column))
                case SQLITE_FLOAT: row[key] = NSNumber(value: sqlite3_column_double(prepared, column))
                case SQLITE_TEXT:
                    let count = Int(sqlite3_column_bytes(prepared, column)); bytes += count
                    guard bytes <= 128 * 1024 * 1024 else { throw LocalRecipeError.invalid("El recetario es demasiado grande para abrirlo de una vez.") }
                    if let pointer = sqlite3_column_text(prepared, column) { row[key] = String(decoding: UnsafeBufferPointer(start: pointer, count: count), as: UTF8.self) }
                case SQLITE_NULL: row[key] = NSNull()
                default: throw LocalRecipeError.invalid("La base contiene un formato no compatible.")
                }
            }
            rows.append(row)
        }
        return ["results": rows, "success": true, "meta": ["changes": Int(sqlite3_changes(database))]]
    }
    func execute(_ statements: [[String: Any]]) async throws -> [[String: Any]] {
        guard statements.count <= 12_000 else { throw LocalRecipeError.invalid("Demasiadas operaciones en la copia.") }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.sql("BEGIN IMMEDIATE")
                    do {
                        let result = try statements.map { item -> [String: Any] in
                            guard let sql = item["sql"] as? String, let values = item["values"] as? [Any] else { throw LocalRecipeError.invalid("Operación local incompleta.") }
                            return try self.statement(sql, values: values)
                        }
                        try self.sql("COMMIT")
                        continuation.resume(returning: result)
                    } catch { try? self.sql("ROLLBACK"); throw error }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func keyValues() async throws -> [String: String] {
        let result = try await execute([["sql": "SELECT key,value FROM native_kv", "values": []]])
        let rows = result.first?["results"] as? [[String: Any]] ?? []
        var values: [String: String] = [:]
        for row in rows { if let key = row["key"] as? String, let value = row["value"] as? String { values[key] = value } }
        return values
    }
    func writeKey(_ key: String, value: String?) async throws {
        guard key.hasPrefix("recetario"), key.utf8.count <= 250, (value?.utf8.count ?? 0) <= 8_000_000 else { throw LocalRecipeError.invalid("El borrador es demasiado grande para guardarlo.") }
        let sql = value == nil ? "DELETE FROM native_kv WHERE key=?" : "INSERT INTO native_kv(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"
        _ = try await execute([["sql": sql, "values": value.map { [key, $0] } ?? [key]]])
    }
}
