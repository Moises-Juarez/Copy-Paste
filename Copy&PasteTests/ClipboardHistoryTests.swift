//
//  ClipboardHistoryTests.swift
//  Copy&PasteTests
//
//  Created by E. Moises Juarez Hernandez on 23/07/2026.
//

import Foundation
import SwiftData
import XCTest
@testable import Copy_Paste

@Model
private final class UnrelatedStoreItem {
    var value: String

    init(value: String) {
        self.value = value
    }
}

@MainActor
final class ClipboardHistoryTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var userDefaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        userDefaultsSuiteName = "ClipboardHistoryTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        userDefaults = nil
        userDefaultsSuiteName = nil
        super.tearDown()
    }

    func testPinnedOrderPersistsAcrossControllers() throws {
        let container = try makeInMemoryContainer()
        let settings = HistoryRetentionSettings(userDefaults: userDefaults)
        let controller = ClipboardController(
            modelContainer: container,
            startsMonitoring: false,
            retentionSettings: settings
        )

        controller.storeClipboardText("Primero")
        controller.storeClipboardText("Segundo")
        controller.storeClipboardText("Tercero")

        let first = try XCTUnwrap(controller.items.first(where: { $0.content == "Primero" }))
        let second = try XCTUnwrap(controller.items.first(where: { $0.content == "Segundo" }))
        let third = try XCTUnwrap(controller.items.first(where: { $0.content == "Tercero" }))

        controller.togglePin(first)
        controller.togglePin(second)
        controller.togglePin(third)
        controller.setPinnedOrder([first, third, second])

        let reloadedController = ClipboardController(
            modelContainer: container,
            startsMonitoring: false,
            retentionSettings: settings
        )

        XCTAssertEqual(
            reloadedController.orderedPinnedItems(from: reloadedController.items).map(\.content),
            ["Primero", "Tercero", "Segundo"]
        )
    }

    func testRetentionRemovesExpiredItemsAndPreservesPinnedItems() throws {
        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        let oldDate = Date().addingTimeInterval(-10 * 24 * 60 * 60)
        context.insert(ClipboardItem(content: "Expirado", copiedAt: oldDate))
        context.insert(ClipboardItem(content: "Fijo", copiedAt: oldDate, isPinned: true))
        try context.save()

        let settings = HistoryRetentionSettings(userDefaults: userDefaults)
        settings.setRetentionDays(7)

        let controller = ClipboardController(
            modelContainer: container,
            startsMonitoring: false,
            retentionSettings: settings
        )
        controller.enforceRetentionPolicy()

        XCTAssertFalse(controller.items.contains(where: { $0.content == "Expirado" }))
        XCTAssertTrue(controller.items.contains(where: { $0.content == "Fijo" }))
    }

    func testStorageEstimateIncludesTextAliasAndImageData() {
        let item = ClipboardItem(
            content: "Texto",
            alternateImage: ClipboardImagePayload(
                data: Data(repeating: 1, count: 32),
                width: nil,
                height: nil
            )
        )
        item.alias = "Alias"
        item.refreshStoredByteCount()

        XCTAssertEqual(item.estimatedStorageBytes, 42)
        XCTAssertEqual(item.contentTypeTitle, "Texto")
    }

    func testStorageLimitKeepsNewestItemAndRemovesOlderOverflow() throws {
        let container = try makeInMemoryContainer()
        let settings = HistoryRetentionSettings(userDefaults: userDefaults)
        settings.setMaxStorageMegabytes(1)
        let controller = ClipboardController(
            modelContainer: container,
            startsMonitoring: false,
            retentionSettings: settings
        )
        let payloadSize = 700 * 1_024

        controller.storeClipboardText(
            "Anterior",
            alternateImage: ClipboardImagePayload(
                data: Data(repeating: 1, count: payloadSize),
                width: nil,
                height: nil
            )
        )
        controller.storeClipboardText(
            "Reciente",
            alternateImage: ClipboardImagePayload(
                data: Data(repeating: 2, count: payloadSize),
                width: nil,
                height: nil
            )
        )

        XCTAssertEqual(controller.items.map(\.content), ["Reciente"])
    }

    func testCachedRowMetadataPerformance() {
        let largeTable = Array(
            repeating: "Columna A\tColumna B\tColumna C\n",
            count: 5_000
        ).joined()
        let item = ClipboardItem(content: largeTable)

        _ = item.preview
        _ = item.hasTabularText

        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(options: options) {
            for _ in 0..<10_000 {
                _ = item.preview
                _ = item.hasTabularText
                _ = item.availablePasteModes
            }
        }
    }

    func testUnavailableFileCleanupKeepsExistingFiles() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let existingFileURL = temporaryDirectory.appendingPathComponent("existente.txt")
        try Data("contenido".utf8).write(to: existingFileURL)
        let missingFileURL = temporaryDirectory.appendingPathComponent("faltante.txt")

        let container = try makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(ClipboardItem(fileURLs: [existingFileURL, missingFileURL]))
        try context.save()

        let settings = HistoryRetentionSettings(userDefaults: userDefaults)
        let controller = ClipboardController(
            modelContainer: container,
            startsMonitoring: false,
            retentionSettings: settings
        )

        controller.refreshFileMetadata()

        for _ in 0..<50 where controller.unavailableFileItemCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(controller.unavailableFileItemCount, 1)
        controller.cleanUnavailableFileReferences()

        let fileItem = try XCTUnwrap(controller.items.first(where: \.isFile))
        XCTAssertEqual(fileItem.fileURLs, [existingFileURL.standardizedFileURL])
        XCTAssertFalse(fileItem.hasUnavailableFiles)
    }

    func testV1StoreMigratesToCurrentSchema() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("Migration.store")
        let legacySchema = Schema(versionedSchema: ClipboardHistorySchemaV1.self)
        let legacyConfiguration = ModelConfiguration(
            "Migration",
            schema: legacySchema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            let legacyContainer = try ModelContainer(
                for: legacySchema,
                configurations: [legacyConfiguration]
            )
            let legacyContext = ModelContext(legacyContainer)
            legacyContext.insert(ClipboardHistorySchemaV1.ClipboardItem(
                content: "Registro anterior",
                isPinned: true,
                alias: "Importante",
                kindRawValue: ClipboardItemKind.text.rawValue
            ))
            try legacyContext.save()
        }

        let currentSchema = Schema(versionedSchema: ClipboardHistorySchemaV3.self)
        let currentConfiguration = ModelConfiguration(
            "Migration",
            schema: currentSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let currentContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: ClipboardHistoryMigrationPlan.self,
            configurations: [currentConfiguration]
        )
        let currentContext = ModelContext(currentContainer)
        let migratedItems = try currentContext.fetch(FetchDescriptor<ClipboardItem>())
        let migratedItem = try XCTUnwrap(migratedItems.first)

        XCTAssertEqual(migratedItem.content, "Registro anterior")
        XCTAssertEqual(migratedItem.displayAlias, "Importante")
        XCTAssertTrue(migratedItem.isPinned)
        XCTAssertNil(migratedItem.pinnedPosition)
        XCTAssertNil(migratedItem.storedByteCount)
    }

    func testV2StoreMigratesToCurrentSchema() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("Current.store")
        let unversionedSchema = Schema(versionedSchema: ClipboardHistorySchemaV2.self)
        let unversionedConfiguration = ModelConfiguration(
            "Current",
            schema: unversionedSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        do {
            let unversionedContainer = try ModelContainer(
                for: unversionedSchema,
                configurations: [unversionedConfiguration]
            )
            let unversionedContext = ModelContext(unversionedContainer)
            unversionedContext.insert(ClipboardHistorySchemaV2.ClipboardItem(
                content: "Registro actual",
                isPinned: true,
                pinnedPosition: 3
            ))
            try unversionedContext.save()
        }

        let currentSchema = Schema(versionedSchema: ClipboardHistorySchemaV3.self)
        let currentConfiguration = ModelConfiguration(
            "Current",
            schema: currentSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let currentContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: ClipboardHistoryMigrationPlan.self,
            configurations: [currentConfiguration]
        )
        let currentContext = ModelContext(currentContainer)
        let migratedItem = try XCTUnwrap(
            try currentContext.fetch(FetchDescriptor<ClipboardItem>()).first
        )

        XCTAssertEqual(migratedItem.content, "Registro actual")
        XCTAssertEqual(migratedItem.pinnedPosition, 3)
    }

    func testStoreValidationAcceptsOnlyClipboardHistoryModels() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let historyStoreURL = temporaryDirectory.appendingPathComponent("History.store")
        let historySchema = Schema(versionedSchema: ClipboardHistorySchemaV1.self)
        let historyConfiguration = ModelConfiguration(
            "History",
            schema: historySchema,
            url: historyStoreURL,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: historySchema,
                configurations: [historyConfiguration]
            )
            let context = ModelContext(container)
            context.insert(ClipboardHistorySchemaV1.ClipboardItem(content: "Historial"))
            try context.save()
        }

        let unrelatedStoreURL = temporaryDirectory.appendingPathComponent("Unrelated.store")
        let unrelatedSchema = Schema([UnrelatedStoreItem.self])
        let unrelatedConfiguration = ModelConfiguration(
            "Unrelated",
            schema: unrelatedSchema,
            url: unrelatedStoreURL,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: unrelatedSchema,
                configurations: [unrelatedConfiguration]
            )
            let context = ModelContext(container)
            context.insert(UnrelatedStoreItem(value: "Otro proyecto"))
            try context.save()
        }

        XCTAssertTrue(Copy_PasteApp.isClipboardHistoryStore(at: historyStoreURL))
        XCTAssertFalse(Copy_PasteApp.isClipboardHistoryStore(at: unrelatedStoreURL))
    }

    func testQuarantinePreservesAllStoreFiles() throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let storeURL = temporaryDirectory.appendingPathComponent("ClipboardHistory.store")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: storeURL.path + "-shm")
        let supportURL = temporaryDirectory.appendingPathComponent(
            ".ClipboardHistory_SUPPORT",
            isDirectory: true
        )

        try Data("store".utf8).write(to: storeURL)
        try Data("wal".utf8).write(to: walURL)
        try Data("shm".utf8).write(to: shmURL)
        try FileManager.default.createDirectory(
            at: supportURL,
            withIntermediateDirectories: true
        )
        try Data("image".utf8).write(to: supportURL.appendingPathComponent("external.data"))

        let recoveryURL = try XCTUnwrap(
            Copy_PasteApp.quarantineStoreFiles(at: storeURL)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportURL.path))

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recoveryURL.appendingPathComponent(storeURL.lastPathComponent).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recoveryURL.appendingPathComponent(walURL.lastPathComponent).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recoveryURL.appendingPathComponent(shmURL.lastPathComponent).path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recoveryURL.appendingPathComponent(supportURL.lastPathComponent).path
            )
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: ClipboardHistorySchemaV3.self)
        let configuration = ModelConfiguration(
            "Tests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: ClipboardHistoryMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopyPasteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
