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
    @Attribute(.unique) var id: UUID
    var content: String
    var copiedAt: Date
    var isPinned: Bool
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
        guard let imageData else {
            return nil
        }

        return NSImage(data: imageData)
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

    var fileIcon: NSImage? {
        guard let firstFileURL = fileURLs.first else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: firstFileURL.path)
    }

    var hasTabularText: Bool {
        kind == .text && ClipboardMonitor.isTabularText(content)
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
        if isFile {
            return filePreview
        }

        if isImage {
            if let imageWidth, let imageHeight {
                return "Captura de pantalla \(Int(imageWidth)) x \(Int(imageHeight))"
            }

            return imageData == nil ? "Imagen no disponible" : "Captura de pantalla"
        }

        return content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
