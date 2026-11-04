import Foundation

enum LocalRecipeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

struct LocalRecipe: Codable {
    var id: String, title: String, ingredients: String = "", steps: String = "", notes: String = ""
    var deleted: Bool = false, revision: Int = 0, operationId: String?
    // Optional additions preserve decoding of the original local v1 file.
    var photoID: String?, sourceURL: String?, collection: String?, favorite: Bool?, deviceRevision: Int?
    func matches(_ other: LocalRecipe) -> Bool { title == other.title && ingredients == other.ingredients && steps == other.steps && notes == other.notes && deleted == other.deleted && photoID == other.photoID && sourceURL == other.sourceURL && (collection ?? "") == (other.collection ?? "") && (favorite ?? false) == (other.favorite ?? false) }
    var mutation: [String: Any] { ["id": id, "title": title, "ingredients": ingredients, "steps": steps, "notes": notes, "deleted": deleted, "baseRevision": revision, "operationId": operationId ?? ""] }
}
struct LocalAccount: Codable { var email: String; var records: [String: LocalRecipe] = [:] }
struct LocalState: Codable {
    var version = 1, active = "guest"
    var guest: [String: LocalRecipe] = [:], accounts: [String: LocalAccount] = [:]
}
struct SyncOutcome: Decodable { let id: String, operationId: String, status: String; let revision: Int? }
struct SyncReply: Decodable { let accountId: String; let outcomes: [SyncOutcome]; let recipes: [LocalRecipe] }

@MainActor final class LocalRecipeStore {
    private(set) var state: LocalState
    let file: URL
    let mediaDirectory: URL
    private let cloudSyncEnabled: Bool
    init(file: URL? = nil, cloudSyncEnabled: Bool = false) throws {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        self.file = file ?? directory.appendingPathComponent("recetario-local-v1.json")
        self.mediaDirectory = self.file.deletingLastPathComponent().appendingPathComponent(self.file.lastPathComponent + ".photos", isDirectory: true)
        self.cloudSyncEnabled = cloudSyncEnabled
        if FileManager.default.fileExists(atPath: self.file.path) {
            state = try JSONDecoder().decode(LocalState.self, from: Data(contentsOf: self.file))
            guard state.version == 1 else { throw LocalRecipeError.invalid("Formato local desconocido. Conserva la copia antes de actualizar.") }
            guard state.active == "guest" || state.accounts[state.active] != nil else { throw LocalRecipeError.invalid("No se puede abrir el recetario guardado. Conserva los datos y tu copia antes de continuar.") }
        } else { state = LocalState() }
    }
    var records: [String: LocalRecipe] { state.active == "guest" ? state.guest : state.accounts[state.active]?.records ?? [:] }
    var visible: [LocalRecipe] { records.values.filter { !$0.deleted }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending } }
    func update(_ edit: (inout LocalState) throws -> Void) throws {
        var next = state; try edit(&next)
        let bytes = try JSONEncoder().encode(next)
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state = next // Never claim a save before the atomic disk write succeeds.
    }
    func put(_ records: [String: LocalRecipe], into s: inout LocalState) {
        if s.active == "guest" { s.guest = records } else { s.accounts[s.active]?.records = records }
    }
    func save(_ recipe: LocalRecipe, expectedScope: String? = nil) throws {
        if let expectedScope, expectedScope != state.active { throw LocalRecipeError.invalid("El recetario ha cambiado. Conserva tu borrador y vuelve a abrirlo.") }
        try Self.validate(recipe)
        if !recipe.deleted, let photoID = recipe.photoID { _ = try photoData(photoID) }
        if let existing = records[recipe.id], existing.revision != recipe.revision || existing.operationId != recipe.operationId || existing.deviceRevision != recipe.deviceRevision { throw LocalRecipeError.invalid("La receta ha cambiado mientras la editabas. Conserva el borrador y vuelve a abrirla.") }
        try update { s in
            var bucket = records, r = recipe
            r.revision = bucket[r.id]?.revision ?? 0
            r.operationId = !cloudSyncEnabled || s.active == "guest" ? nil : UUID().uuidString.lowercased()
            r.deviceRevision = (bucket[r.id]?.deviceRevision ?? 0) + 1
            bucket[r.id] = r; put(bucket, into: &s)
        }
    }
    static func validate(_ recipe: LocalRecipe) throws {
        guard !recipe.id.isEmpty, recipe.id.utf8.count <= 128,
              !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LocalRecipeError.invalid("Pon un nombre a la receta.") }
        guard recipe.title.utf16.count <= 180, recipe.ingredients.utf16.count <= 20000,
              recipe.steps.utf16.count <= 24000, recipe.notes.utf16.count <= 12000,
              (recipe.collection ?? "").utf16.count <= 100 else { throw LocalRecipeError.invalid("La receta es demasiado larga. Revisa el texto antes de guardarla.") }
        if let source = recipe.sourceURL, !source.isEmpty {
            guard source.utf8.count <= 2048, let url = URL(string: source),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, url.user == nil, url.password == nil else { throw LocalRecipeError.invalid("El enlace de origen no es válido.") }
        }
        if let photo = recipe.photoID { guard Self.validPhotoID(photo) else { throw LocalRecipeError.invalid("La referencia de la foto no es válida.") } }
    }
    func delete(_ recipe: LocalRecipe) throws { var removed = recipe; removed.deleted = true; try save(removed) }
    func detach() throws { try update { $0.active = "guest" } }
    func removeAccount(_ id:String) throws {try update { s in s.accounts.removeValue(forKey:id);if s.active==id{s.active="guest"} }}
    func link(accountId: String, email: String, remote: [LocalRecipe]) throws {
        guard cloudSyncEnabled else { throw LocalRecipeError.invalid("La sincronización no está disponible en esta versión local.") }
        guard state.active == "guest" || state.active == accountId else { throw LocalRecipeError.invalid("Cierra la cuenta anterior antes de cambiar de cuenta.") }
        try update { s in
            var account = s.accounts[accountId] ?? LocalAccount(email: email); account.email = email
            for r in remote where account.records[r.id]?.operationId == nil { account.records[r.id] = r }
            for g in s.guest.values where !g.deleted {
                if account.records.values.contains(where: { $0.matches(g) }) { continue }
                var r = g
                if account.records[r.id] != nil { r.id = UUID().uuidString.lowercased() }
                r.revision = 0; r.operationId = UUID().uuidString.lowercased(); account.records[r.id] = r
            }
            s.accounts[accountId] = account; s.guest = [:]; s.active = accountId
        }
    }
    func batch() throws -> [String: Any] {
        guard cloudSyncEnabled else { throw LocalRecipeError.invalid("La sincronización no está disponible en esta versión local.") }
        guard state.active != "guest" else { throw LocalRecipeError.invalid("No hay una cuenta vinculada.") }
        var selected: [[String: Any]] = [], bytes = 0
        for r in records.values.sorted(by: { $0.id < $1.id }) where r.operationId != nil {
            let m = r.mutation, size = try JSONSerialization.data(withJSONObject: m).count
            if selected.count == 50 || bytes + size > 1500000 { break }
            selected.append(m); bytes += size
        }
        return ["expectedAccountId": state.active, "mutations": selected]
    }
    func apply(_ reply: SyncReply, sent: [String: Any]) throws {
        guard cloudSyncEnabled else { throw LocalRecipeError.invalid("La sincronización no está disponible en esta versión local.") }
        guard let expected = sent["expectedAccountId"] as? String, state.active == expected, reply.accountId == expected else { throw LocalRecipeError.invalid("La cuenta ha cambiado. Se conserva la copia local.") }
        let mutations = sent["mutations"] as? [[String: Any]] ?? []
        let remote = Dictionary(uniqueKeysWithValues: reply.recipes.map { ($0.id, $0) })
        try update { s in
            var bucket = records
            func conflictCopy(_ local: LocalRecipe) {
                guard !local.deleted else { return }; var copy = local
                copy.id = UUID().uuidString.lowercased(); copy.title = String(local.title.prefix(160)) + " (copia de conflicto)"
                copy.revision = 0; copy.operationId = UUID().uuidString.lowercased(); bucket[copy.id] = copy
            }
            for outcome in reply.outcomes {
                guard var local = bucket[outcome.id], let mutation = mutations.first(where: { ($0["id"] as? String) == outcome.id }), (mutation["operationId"] as? String) == outcome.operationId else { continue }
                let r = remote[outcome.id]
                if local.operationId != outcome.operationId {
                    if local.operationId == nil { continue }
                    if outcome.status == "applied", let r, r.revision == outcome.revision { local.revision = r.revision; bucket[local.id] = local }
                    else if let r, !local.deleted { conflictCopy(local); bucket[outcome.id] = r }
                    continue
                }
                if outcome.status == "conflict", !local.deleted, r.map({ !local.matches($0) }) ?? true { conflictCopy(local) }
                bucket[outcome.id] = r
            }
            for r in reply.recipes where bucket[r.id]?.operationId == nil && (bucket[r.id]?.revision ?? 0) <= r.revision { bucket[r.id] = r }
            put(bucket, into: &s)
        }
    }
}
