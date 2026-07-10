//
//  AppIconRepository.swift
//  StikDebug
//

import SwiftUI
import UIKit
import ImageIO

enum AppIconRepository {
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 2_000
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private static let diskQueue = DispatchQueue(label: "com.stik.iconcache.disk", qos: .utility)
    /// Allow a few concurrent icon fetches so list scrolling doesn't serialize behind one request.
    private static let fetchSemaphore = AsyncSemaphore(permits: 4)
    private static let registry = IconFetchRegistry()
    private static let appGroupIdentifier = "group.com.stik.sj"
    private static let thumbnailPixelSize = 180
    private static let iconDirectory: URL? = {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }

        let directory = container.appendingPathComponent("icons", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }()

    static func cachedImage(for bundleID: String) -> UIImage? {
        memory.object(forKey: bundleID as NSString)
    }

    static func image(for bundleID: String) async -> UIImage? {
        if let memoryImage = cachedImage(for: bundleID) {
            return memoryImage
        }

        if let diskImage = await loadFromDisk(bundleID: bundleID) {
            storeInMemory(diskImage, for: bundleID)
            return diskImage
        }

        return await fetchAndStore(bundleID: bundleID)
    }

    static func prefetch(bundleIDs: [String]) {
        let unique = Array(Set(bundleIDs))
        guard !unique.isEmpty else { return }

        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for bundleID in unique {
                    group.addTask {
                        _ = await image(for: bundleID)
                    }
                }
            }
        }
    }

    private static func fetchAndStore(bundleID: String) async -> UIImage? {
        let task = await registry.task(for: bundleID) {
            Task.detached(priority: .utility) {
                await fetchSemaphore.acquire()

                let result: UIImage?
                if let data = await fetchFromSource(bundleID: bundleID),
                   let thumbnail = makeThumbnail(from: data) {
                    let prepared = prepareForDisplay(thumbnail)
                    store(prepared, for: bundleID)
                    result = prepared
                } else {
                    result = nil
                }

                await fetchSemaphore.release()
                await registry.clear(bundleID: bundleID)
                return result
            }
        }

        return await task.value
    }

    private static func fetchFromSource(bundleID: String) async -> Data? {
        await withCheckedContinuation { continuation in
            AppStoreIconFetcher.getIconData(for: bundleID) { data in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadFromDisk(bundleID: String) async -> UIImage? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            diskQueue.async {
                guard let url = iconURL(for: bundleID),
                      FileManager.default.fileExists(atPath: url.path) else {
                    continuation.resume(returning: nil)
                    return
                }

                guard let data = try? Data(contentsOf: url) else {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: nil)
                    return
                }

                guard let image = makeThumbnail(from: data) else {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: prepareForDisplay(image))
            }
        }
    }

    private static func store(_ image: UIImage, for bundleID: String) {
        storeInMemory(image, for: bundleID)
        storeOnDisk(image, bundleID: bundleID)
    }

    private static func storeInMemory(_ image: UIImage, for bundleID: String) {
        memory.setObject(image, forKey: bundleID as NSString, cost: memoryCost(for: image))
    }

    private static func storeOnDisk(_ image: UIImage, bundleID: String) {
        diskQueue.async {
            guard let url = iconURL(for: bundleID),
                  let data = image.pngData() else {
                return
            }

            try? data.write(to: url, options: .atomic)
        }
    }

    private static func iconURL(for bundleID: String) -> URL? {
        guard let directory = iconDirectory,
              let fileName = cacheFileName(for: bundleID) else {
            return nil
        }
        return directory.appendingPathComponent(fileName)
    }

    private static func cacheFileName(for bundleID: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let sanitized = String(bundleID.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        })

        guard !sanitized.isEmpty else {
            return nil
        }

        return "\(sanitized).png"
    }

    private static func memoryCost(for image: UIImage) -> Int {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        return max(width * height * 4, 1)
    }

    private static func prepareForDisplay(_ image: UIImage) -> UIImage {
        image.preparingForDisplay() ?? image
    }

    private static func makeThumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}

@MainActor
final class IconLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private let bundleID: String
    private var didStart = false

    init(bundleID: String) {
        self.bundleID = bundleID
        image = AppIconRepository.cachedImage(for: bundleID)
        didStart = image != nil
    }

    func beginLoading() {
        guard image == nil, !didStart else { return }
        didStart = true
        let targetID = bundleID
        Task { [weak self] in
            let resolved = await AppIconRepository.image(for: targetID)
            guard let self else { return }
            if let resolved {
                self.image = resolved
            } else {
                self.didStart = false
            }
        }
    }
}

private actor IconFetchRegistry {
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func task(for bundleID: String, create: () -> Task<UIImage?, Never>) -> Task<UIImage?, Never> {
        if let existing = tasks[bundleID] {
            return existing
        }

        let task = create()
        tasks[bundleID] = task
        return task
    }

    func clear(bundleID: String) {
        tasks[bundleID] = nil
    }
}

private actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) {
        self.permits = permits
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            permits += 1
        }
    }
}
