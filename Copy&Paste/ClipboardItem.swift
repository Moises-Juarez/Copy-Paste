//
//  ClipboardItem.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import Foundation
import SwiftData

enum ClipboardItemKind: String {
    case text
    case image
    case file
}

enum ClipboardPasteMode: String, CaseIterable, Identifiable {
    case automatic
    case table
    case plainText
    case image

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .automatic:
            return "Pegar automatico"
        case .table:
            return "Pegar como tabla"
        case .plainText:
            return "Pegar sin formato"
        case .image:
            return "Pegar como imagen"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic:
            return "doc.on.clipboard"
        case .table:
            return "tablecells"
        case .plainText:
            return "textformat"
        case .image:
            return "photo"
        }
    }
}

@Model
final class ClipboardItem {
    private static let imageCache: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.totalCostLimit = 128 * 1_024 * 1_024
        return cache
    }()
    private static let previewCache: NSCache<NSUUID, NSString> = {
        let cache = NSCache<NSUUID, NSString>()
        cache.countLimit = 2_000
        return cache
    }()
    private static let tabularTextCache: NSCache<NSUUID, NSNumber> = {
        let cache = NSCache<NSUUID, NSNumber>()
        cache.countLimit = 2_000
        return cache
    }()

    @Attribute(.unique) var id: UUID
    var content: String
    var copiedAt: Date
    var isPinned: Bool
    var pinnedPosition: Int?
    var storedByteCount: Int64?
    var alias: String?
    var kindRawValue: String?
    @Attribute(.externalStorage) var imageData: Data?
    var imageWidth: Double?
    var imageHeight: Double?

    init(
        content: String,
        copiedAt: Date = .now,
        isPinned: Bool = false,
        alternateImage: ClipboardImagePayload? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.pinnedPosition = nil
        self.storedByteCount = Int64(content.lengthOfBytes(using: .utf8) + (alternateImage?.data.count ?? 0))
        self.alias = nil
        self.kindRawValue = ClipboardItemKind.text.rawValue
        self.imageData = alternateImage?.data
        self.imageWidth = alternateImage?.width
        self.imageHeight = alternateImage?.height
    }

    init(
        imageData: Data,
        imageWidth: Double? = nil,
        imageHeight: Double? = nil,
        copiedAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.content = ""
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.pinnedPosition = nil
        self.storedByteCount = Int64(imageData.count)
        self.alias = nil
        self.kindRawValue = ClipboardItemKind.image.rawValue
        self.imageData = imageData
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    init(
        fileURLs: [URL],
        copiedAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = UUID()
        self.content = Self.fileContent(from: fileURLs)
        self.copiedAt = copiedAt
        self.isPinned = isPinned
        self.pinnedPosition = nil
        self.storedByteCount = Int64(content.lengthOfBytes(using: .utf8))
        self.alias = nil
        self.kindRawValue = ClipboardItemKind.file.rawValue
        self.imageData = nil
        self.imageWidth = nil
        self.imageHeight = nil
    }

    var kind: ClipboardItemKind {
        if let kindRawValue,
           let kind = ClipboardItemKind(rawValue: kindRawValue) {
            return kind
        }

        if imageData != nil {
            return .image
        }

        return .text
    }

    var isImage: Bool {
        kind == .image
    }

    var isFile: Bool {
        kind == .file
    }

    var displayAlias: String? {
        guard let alias else {
            return nil
        }

        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedAlias.isEmpty ? nil : trimmedAlias
    }

    var image: NSImage? {
        let cacheKey = id as NSUUID

        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let imageData else {
            return nil
        }

        guard let image = NSImage(data: imageData) else {
            return nil
        }

        Self.imageCache.setObject(image, forKey: cacheKey, cost: imageData.count)
        return image
    }

    var alternateImagePayload: ClipboardImagePayload? {
        guard let imageData, !imageData.isEmpty else {
            return nil
        }

        return ClipboardImagePayload(data: imageData, width: imageWidth, height: imageHeight)
    }

    var fileURLs: [URL] {
        guard isFile else {
            return []
        }

        return Self.filePaths(from: content).map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
    }

    var existingFileURLs: [URL] {
        fileURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    var unavailableFileCount: Int {
        guard isFile else {
            return 0
        }

        return max(fileURLs.count - existingFileURLs.count, 0)
    }

    var hasUnavailableFiles: Bool {
        unavailableFileCount > 0
    }

    var estimatedStorageBytes: Int64 {
        storedByteCount ?? calculatedStorageBytes
    }

    var knownStorageBytes: Int64 {
        storedByteCount ?? Int64(
            content.lengthOfBytes(using: .utf8)
                + (alias?.lengthOfBytes(using: .utf8) ?? 0)
        )
    }

    func refreshStoredByteCount() {
        storedByteCount = calculatedStorageBytes
    }

    private var calculatedStorageBytes: Int64 {
        let contentBytes = Int64(content.lengthOfBytes(using: .utf8))
        let aliasBytes = Int64(alias?.lengthOfBytes(using: .utf8) ?? 0)
        let imageBytes = Int64(imageData?.count ?? 0)
        return contentBytes + aliasBytes + imageBytes
    }

    var representedContentBytes: Int64 {
        guard isFile else {
            return estimatedStorageBytes
        }

        return existingFileURLs.reduce(into: Int64(0)) { total, fileURL in
            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            total += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
    }

    var contentTypeTitle: String {
        switch kind {
        case .text:
            return hasTabularText ? "Tabla" : "Texto"
        case .image:
            return "Imagen"
        case .file:
            let count = fileURLs.count
            return count == 1 ? "Archivo" : "\(count) archivos"
        }
    }

    var contentTypeSystemImage: String {
        switch kind {
        case .text:
            return hasTabularText ? "tablecells" : "doc.text"
        case .image:
            return "photo"
        case .file:
            return "doc"
        }
    }

    var representedSizeDescription: String {
        if isFile && existingFileURLs.isEmpty {
            return "No disponible"
        }

        return ByteCountFormatter.string(
            fromByteCount: representedContentBytes,
            countStyle: .file
        )
    }

    func invalidateVisualCache() {
        let cacheKey = id as NSUUID
        Self.imageCache.removeObject(forKey: cacheKey)
        Self.previewCache.removeObject(forKey: cacheKey)
        Self.tabularTextCache.removeObject(forKey: cacheKey)
    }

    var hasTabularText: Bool {
        guard kind == .text else {
            return false
        }

        let cacheKey = id as NSUUID

        if let cachedResult = Self.tabularTextCache.object(forKey: cacheKey) {
            return cachedResult.boolValue
        }

        let isTabular = ClipboardMonitor.isTabularText(content)
        Self.tabularTextCache.setObject(NSNumber(value: isTabular), forKey: cacheKey)
        return isTabular
    }

    var availablePasteModes: [ClipboardPasteMode] {
        switch kind {
        case .text:
            var modes: [ClipboardPasteMode] = [.automatic, .plainText]

            if hasTabularText {
                modes.insert(.table, at: 1)
            }

            if alternateImagePayload != nil {
                modes.append(.image)
            }

            return modes
        case .image:
            return [.automatic]
        case .file:
            return [.automatic]
        }
    }

    var preview: String {
        let cacheKey = id as NSUUID

        if let cachedPreview = Self.previewCache.object(forKey: cacheKey) {
            return cachedPreview as String
        }

        let generatedPreview: String

        if isFile {
            generatedPreview = filePreview
        } else if isImage {
            if let imageWidth, let imageHeight {
                generatedPreview = "Captura de pantalla \(Int(imageWidth)) x \(Int(imageHeight))"
            } else {
                generatedPreview = imageData == nil ? "Imagen no disponible" : "Captura de pantalla"
            }
        } else {
            generatedPreview = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        Self.previewCache.setObject(generatedPreview as NSString, forKey: cacheKey)
        return generatedPreview
    }

    var menuTitle: String {
        guard let displayAlias else {
            return preview
        }

        let itemPreview = preview
        return itemPreview.isEmpty ? displayAlias : "\(displayAlias) - \(itemPreview)"
    }

    func matchesSearch(_ query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuery.isEmpty else {
            return true
        }

        return preview.localizedCaseInsensitiveContains(normalizedQuery)
            || content.localizedCaseInsensitiveContains(normalizedQuery)
            || (displayAlias?.localizedCaseInsensitiveContains(normalizedQuery) ?? false)
    }

    private var filePreview: String {
        let fileURLs = fileURLs

        guard !fileURLs.isEmpty else {
            return "Archivos no disponibles"
        }

        let names = fileURLs.map(\.lastPathComponent)

        if names.count == 1 {
            return names[0]
        }

        let firstNames = names.prefix(3).joined(separator: ", ")
        let remainingCount = names.count - 3

        if remainingCount > 0 {
            return "\(names.count) archivos: \(firstNames) y \(remainingCount) mas"
        }

        return "\(names.count) archivos: \(firstNames)"
    }

    static func fileContent(from fileURLs: [URL]) -> String {
        fileURLs
            .map { $0.standardizedFileURL.path }
            .joined(separator: "\n")
    }

    static func filePaths(from content: String) -> [String] {
        content
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
