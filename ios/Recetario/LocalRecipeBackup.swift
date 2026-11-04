import Foundation
import CryptoKit
import ImageIO

struct LocalRecipeBackup: Codable {
    var format = "krazel-recetario-local", version = 1
    var createdAt = Date()
    var recipes: [LocalRecipe]
    var photos: [String: Data]
}

struct LocalRestorePreview {
    let backup: LocalRecipeBackup
    let scope: String
    var count: Int { backup.recipes.count }
}

@MainActor extension LocalRecipeStore {
    nonisolated static let maximumBackupBytes = 128 * 1024 * 1024
    nonisolated static let maximumPhotoBytes = 1024 * 1024
    static func validPhotoID(_ id: String) -> Bool {
        id.utf8.count == 68 && id.hasSuffix(".jpg") && id.dropLast(4).allSatisfy { "0123456789abcdef".contains($0) }
    }
    static func photoID(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
    static func validatePhoto(_ data: Data, id: String) throws {
        guard validPhotoID(id), !data.isEmpty, data.count <= maximumPhotoBytes,
              photoID(data) == id,
              let image = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) == 1,
              (CGImageSourceGetType(image) as String?) == "public.jpeg",
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 2000, height <= 2000,
              CGImageSourceCreateImageAtIndex(image, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else {
            throw LocalRecipeError.invalid("La copia contiene una foto dañada o demasiado grande.")
        }
    }
    func photoData(_ id: String) throws -> Data {
        guard Self.validPhotoID(id) else { throw LocalRecipeError.invalid("La foto no es válida.") }
        let url = mediaDirectory.appendingPathComponent(id)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= Self.maximumPhotoBytes else { throw LocalRecipeError.invalid("La foto es demasiado grande.") }
        let data = try Data(contentsOf: url)
        try Self.validatePhoto(data, id: id)
        return data
    }
    @discardableResult func savePhoto(_ data: Data) throws -> String {
        let id = Self.photoID(data)
        try Self.validatePhoto(data, id: id)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let destination = mediaDirectory.appendingPathComponent(id)
        // Content-addressed, immutable files. Rewriting also repairs a damaged photo
        // from a validated backup; the current recipe database is never replaced here.
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return id
    }
    func makeBackup() throws -> Data {
        var recipes = visible, photos: [String: Data] = [:], total = 0
        guard recipes.count <= 5000 else { throw LocalRecipeError.invalid("Exporta una selección más pequeña de recetas.") }
        for index in recipes.indices {
            total += recipes[index].title.utf8.count + recipes[index].ingredients.utf8.count + recipes[index].steps.utf8.count + recipes[index].notes.utf8.count
            guard total <= Self.maximumBackupBytes / 2 else { throw LocalRecipeError.invalid("La copia supera el tamaño admitido.") }
            recipes[index].operationId = nil
            recipes[index].revision = 0
            recipes[index].deviceRevision = nil
            if let id = recipes[index].photoID, photos[id] == nil {
                let data = try photoData(id)
                total += data.count
                guard total <= Self.maximumBackupBytes / 2 else { throw LocalRecipeError.invalid("La copia supera el tamaño admitido. Exporta menos fotos a la vez.") }
                photos[id] = data
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(LocalRecipeBackup(recipes: recipes, photos: photos))
        guard bytes.count <= Self.maximumBackupBytes else { throw LocalRecipeError.invalid("La copia es demasiado grande.") }
        return bytes
    }
    func previewBackup(_ data: Data) throws -> LocalRestorePreview {
        guard data.count <= Self.maximumBackupBytes else { throw LocalRecipeError.invalid("La copia supera los 128 MB admitidos.") }
        let backup: LocalRecipeBackup
        if data.first(where: { ![9,10,13,32].contains($0) }) == 91 {
            // Accept text-only exports made by the previous iPhone candidate.
            backup = LocalRecipeBackup(recipes: try JSONDecoder().decode([LocalRecipe].self, from: data), photos: [:])
        } else { backup = try JSONDecoder().decode(LocalRecipeBackup.self, from: data) }
        guard backup.format == "krazel-recetario-local", backup.version == 1,
              backup.recipes.count <= 5000, backup.photos.count <= 5000 else {
            throw LocalRecipeError.invalid("Este archivo no es una copia compatible de Recetario.")
        }
        var ids = Set<String>(), photoIDs = Set<String>()
        for recipe in backup.recipes {
            try Self.validate(recipe)
            guard !recipe.deleted, ids.insert(recipe.id).inserted else { throw LocalRecipeError.invalid("La copia contiene recetas repetidas o eliminadas.") }
            if let photo = recipe.photoID { photoIDs.insert(photo) }
        }
        guard photoIDs == Set(backup.photos.keys) else { throw LocalRecipeError.invalid("La copia no contiene todas sus fotos o incluye archivos sin receta.") }
        for (id, photo) in backup.photos { try Self.validatePhoto(photo, id: id) }
        return LocalRestorePreview(backup: backup, scope: state.active)
    }
    @discardableResult func restore(_ preview: LocalRestorePreview) throws -> Int {
        guard preview.scope == state.active else { throw LocalRecipeError.invalid("El recetario ha cambiado. Abre de nuevo la copia.") }
        // No recipe changes until ALL media is validated and written. An interrupted
        // restore can leave harmless unreferenced photos, never dangling recipes.
        for (_, photo) in preview.backup.photos { try savePhoto(photo) }
        var added = 0
        try update { next in
            var bucket = records
            for original in preview.backup.recipes {
                if bucket.values.contains(where: { !$0.deleted && $0.matches(original) }) { continue }
                var recipe = original
                if bucket[recipe.id] != nil { recipe.id = UUID().uuidString.lowercased() }
                recipe.revision = 0; recipe.operationId = nil; recipe.deviceRevision = 1
                bucket[recipe.id] = recipe
                added += 1
            }
            put(bucket, into: &next)
        }
        return added
    }
}
