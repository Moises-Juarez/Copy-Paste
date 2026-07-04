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
        }
    }

    var preview: String {
        guard !isImage else {
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
}
