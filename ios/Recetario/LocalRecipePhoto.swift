import UIKit
import ImageIO

enum LocalRecipePhoto {
    // Downsample before decoding a camera-sized original, orient it, then encode
    // fresh JPEG pixels so library metadata/location does not enter the backup.
    static func compressedFile(at url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { throw LocalRecipeError.invalid("No se pudo abrir esa imagen.") }
        let image = UIImage(cgImage: cgImage)
        for quality in [0.8, 0.65, 0.45, 0.25] {
            if let bytes = image.jpegData(compressionQuality: quality), bytes.count <= LocalRecipeStore.maximumPhotoBytes {
                return bytes
            }
        }
        throw LocalRecipeError.invalid("No se ha podido reducir el tamaño de la foto. Prueba con otra imagen.")
    }
}
