import SwiftUI
import AppKit

// MARK: - Icon Cache

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 100
        // Cap total cache at ~20MB. Each 64x64 NSImage is ~16KB bitmap +
        // representation overhead, so 100 images ≈ 1.6MB bitmap data.
        // The limit is a safety net for unusually large icons.
        cache.totalCostLimit = 20 * 1024 * 1024
    }

    func icon(for bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image = loadIcon(for: bundleID)
        if let image = image {
            // Estimate cost from bitmap size (bytes per pixel * width * height).
            let cost = Int(image.size.width * image.size.height) * 4
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    private func loadIcon(for bundleID: String) -> NSImage? {
        // Try to get icon from running app first
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return resize(runningApp.icon)
        }

        // If not running, try to get icon from app path
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return resize(NSWorkspace.shared.icon(forFile: appURL.path))
        }

        return nil
    }

    private func resize(_ image: NSImage?) -> NSImage? {
        guard let image = image else { return nil }
        let targetSize = NSSize(width: 64, height: 64)
        guard image.size.width > targetSize.width || image.size.height > targetSize.height else {
            return image
        }

        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        resized.unlockFocus()
        return resized
    }
}
