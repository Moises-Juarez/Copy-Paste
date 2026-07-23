//
//  ClipboardHistorySchema.swift
//  Copy&Paste
//
//  Created by E. Moises Juarez Hernandez on 23/07/2026.
//

import Foundation
import SwiftData

enum ClipboardHistorySchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ClipboardItem.self]
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
            id: UUID = UUID(),
            content: String,
            copiedAt: Date = .now,
            isPinned: Bool = false,
            alias: String? = nil,
            kindRawValue: String? = nil,
            imageData: Data? = nil,
            imageWidth: Double? = nil,
            imageHeight: Double? = nil
        ) {
            self.id = id
            self.content = content
            self.copiedAt = copiedAt
            self.isPinned = isPinned
            self.alias = alias
            self.kindRawValue = kindRawValue
            self.imageData = imageData
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
        }
    }
}

enum ClipboardHistorySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ClipboardItem.self]
    }

    @Model
    final class ClipboardItem {
        @Attribute(.unique) var id: UUID
        var content: String
        var copiedAt: Date
        var isPinned: Bool
        var pinnedPosition: Int?
        var alias: String?
        var kindRawValue: String?
        @Attribute(.externalStorage) var imageData: Data?
        var imageWidth: Double?
        var imageHeight: Double?

        init(
            id: UUID = UUID(),
            content: String,
            copiedAt: Date = .now,
            isPinned: Bool = false,
            pinnedPosition: Int? = nil,
            alias: String? = nil,
            kindRawValue: String? = nil,
            imageData: Data? = nil,
            imageWidth: Double? = nil,
            imageHeight: Double? = nil
        ) {
            self.id = id
            self.content = content
            self.copiedAt = copiedAt
            self.isPinned = isPinned
            self.pinnedPosition = pinnedPosition
            self.alias = alias
            self.kindRawValue = kindRawValue
            self.imageData = imageData
            self.imageWidth = imageWidth
            self.imageHeight = imageHeight
        }
    }
}

enum ClipboardHistorySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ClipboardItem.self]
    }
}

enum ClipboardHistoryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            ClipboardHistorySchemaV1.self,
            ClipboardHistorySchemaV2.self,
            ClipboardHistorySchemaV3.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: ClipboardHistorySchemaV1.self,
                toVersion: ClipboardHistorySchemaV2.self
            ),
            .lightweight(
                fromVersion: ClipboardHistorySchemaV2.self,
                toVersion: ClipboardHistorySchemaV3.self
            ),
        ]
    }
}
