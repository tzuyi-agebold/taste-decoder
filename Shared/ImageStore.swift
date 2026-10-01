import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Saves images as downsampled JPEGs on disk and serves cached thumbnails.
/// Models only keep the file name.
enum ImageStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static func url(for name: String) -> URL {
        AppGroup.imagesDirectory.appendingPathComponent(name)
    }

    /// Downsamples encoded image data (JPEG, HEIC, PNG…) and stores it. Returns the file name.
    @discardableResult
    static func save(data: Data, maxPixel: CGFloat = 2048) -> String? {
        guard let image = downsample(data: data, maxPixel: maxPixel) else { return nil }
        return save(cgImage: image)
    }

    @discardableResult
    static func save(image: UIImage, maxPixel: CGFloat = 2048) -> String? {
        let longest = max(image.size.width, image.size.height) * image.scale
        if longest > maxPixel, let data = image.jpegData(compressionQuality: 0.95) {
            return save(data: data, maxPixel: maxPixel)
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        return write(data)
    }

    static func data(named name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    static func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// A decoded, downsampled image suitable for display. Cached by name and size.
    static func image(named name: String, maxPixel: CGFloat) -> UIImage? {
        let cacheKey = "\(name)@\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let data = data(named: name), let cgImage = downsample(data: data, maxPixel: maxPixel) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    /// JPEG sized for Claude's vision input (long edge ≤ 1568 px).
    static func jpegForUpload(named name: String, maxPixel: CGFloat = 1568) -> Data? {
        guard let data = data(named: name), let cgImage = downsample(data: data, maxPixel: maxPixel) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    static func delete(named name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
        cache.removeAllObjects()
    }

    // MARK: - Private

    private static func save(cgImage: CGImage) -> String? {
        guard let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.85) else { return nil }
        return write(data)
    }

    private static func write(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(for: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// ImageIO thumbnailing: decodes only what's needed and applies EXIF orientation.
    static func downsample(data: Data, maxPixel: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
