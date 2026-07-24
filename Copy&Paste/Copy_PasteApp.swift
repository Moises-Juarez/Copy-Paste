//
//  Copy_PasteApp.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import Foundation
import CoreData
import SwiftUI
import SwiftData

@main
struct Copy_PasteApp: App {
    private let globalHotKeyController: GlobalHotKeyController

    @StateObject private var historyRetentionSettings: HistoryRetentionSettings
    @StateObject private var clipboardController: ClipboardController
    @StateObject private var accessibilityPermissionController: AccessibilityPermissionController
    @StateObject private var historyWindowController: HistoryWindowController
    @StateObject private var launchAtLoginController = LaunchAtLoginController()

    init() {
        let modelContainer = Self.makeModelContainer()
        let historyRetentionSettings = HistoryRetentionSettings()
        let clipboardController = ClipboardController(
            modelContainer: modelContainer,
            retentionSettings: historyRetentionSettings
        )
        let accessibilityPermissionController = AccessibilityPermissionController()
        let historyWindowController = HistoryWindowController(
            clipboardController: clipboardController,
            accessibilityPermissionController: accessibilityPermissionController,
            modelContainer: modelContainer
        )
        let globalHotKeyController = GlobalHotKeyController()
        globalHotKeyController.registerCommandShiftV {
            Task { @MainActor in
                historyWindowController.show()
            }
        }
        Task { @MainActor in
            historyWindowController.prepareWindow()
        }

        self.globalHotKeyController = globalHotKeyController
        self._historyRetentionSettings = StateObject(wrappedValue: historyRetentionSettings)
        self._clipboardController = StateObject(wrappedValue: clipboardController)
        self._accessibilityPermissionController = StateObject(wrappedValue: accessibilityPermissionController)
        self._historyWindowController = StateObject(wrappedValue: historyWindowController)
    }

    var body: some Scene {
        MenuBarExtra {
            ClipboardMenuView()
                .environmentObject(clipboardController)
                .environmentObject(accessibilityPermissionController)
                .environmentObject(globalHotKeyController)
                .environmentObject(historyWindowController)
                .environmentObject(launchAtLoginController)
                .environmentObject(historyRetentionSettings)
        } label: {
            Label("Copy&Paste", systemImage: "doc.on.clipboard")
        }
        .menuBarExtraStyle(.menu)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: ClipboardHistorySchemaV3.self)

        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            do {
                let testConfiguration = ModelConfiguration(
                    "ClipboardHistoryTests",
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )

                return try ModelContainer(
                    for: schema,
                    migrationPlan: ClipboardHistoryMigrationPlan.self,
                    configurations: [testConfiguration]
                )
            } catch {
                fatalError("Could not create the test ModelContainer: \(error)")
            }
        }

        do {
            let storeURL = try clipboardHistoryStoreURL()
            try quarantineIncompatibleStoreIfNeeded(at: storeURL)
            try migrateDefaultStoreIfNeeded(to: storeURL)
            return try makePersistentModelContainer(schema: schema, storeURL: storeURL)
        } catch {
            NSLog("Copy&Paste could not open its history store: \(error)")

            do {
                let storeURL = try clipboardHistoryStoreURL()
                let recoveryURL = try quarantineStoreFiles(at: storeURL)

                if let recoveryURL {
                    NSLog("Copy&Paste preserved the incompatible store at \(recoveryURL.path)")
                }

                try migrateDefaultStoreIfNeeded(to: storeURL)
                return try makePersistentModelContainer(schema: schema, storeURL: storeURL)
            } catch {
                NSLog("Copy&Paste is using temporary in-memory history: \(error)")

                do {
                    return try makeInMemoryModelContainer(schema: schema)
                } catch {
                    fatalError("Could not create a fallback ModelContainer: \(error)")
                }
            }
        }
    }

    private static func makePersistentModelContainer(
        schema: Schema,
        storeURL: URL
    ) throws -> ModelContainer {
        let modelConfiguration = ModelConfiguration(
            "ClipboardHistory",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: ClipboardHistoryMigrationPlan.self,
            configurations: [modelConfiguration]
        )
    }

    private static func makeInMemoryModelContainer(schema: Schema) throws -> ModelContainer {
        let modelConfiguration = ModelConfiguration(
            "ClipboardHistoryFallback",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: ClipboardHistoryMigrationPlan.self,
            configurations: [modelConfiguration]
        )
    }

    private static func clipboardHistoryStoreURL() throws -> URL {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Copy&Paste", isDirectory: true)

        try FileManager.default.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true
        )

        return appSupportURL.appendingPathComponent("ClipboardHistory.store")
    }

    private static func migrateDefaultStoreIfNeeded(to targetStoreURL: URL) throws {
        let fileManager = FileManager.default

        guard !fileManager.fileExists(atPath: targetStoreURL.path),
              let sourceStoreURL = mostRecentExistingDefaultStoreURL() else {
            return
        }

        try fileManager.createDirectory(
            at: targetStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try copyStoreFiles(from: sourceStoreURL, to: targetStoreURL)
        try copyExternalDataDirectoryIfNeeded(from: sourceStoreURL, to: targetStoreURL)
    }

    private static func mostRecentExistingDefaultStoreURL() -> URL? {
        defaultStoreCandidates()
            .filter {
                FileManager.default.fileExists(atPath: $0.path)
                    && isClipboardHistoryStore(at: $0)
            }
            .max { lhs, rhs in
                modificationDate(for: lhs) < modificationDate(for: rhs)
            }
    }

    static func isClipboardHistoryStore(at storeURL: URL) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: storeURL
        ),
        let versionHashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] else {
            return false
        }

        return versionHashes.keys.contains("ClipboardItem")
    }

    private static func quarantineIncompatibleStoreIfNeeded(at storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              !isClipboardHistoryStore(at: storeURL) else {
            return
        }

        _ = try quarantineStoreFiles(at: storeURL)
    }

    private static func defaultStoreCandidates() -> [URL] {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        let containerSupportURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/Moises-Juarez.Copy-Paste/Data/Library/Application Support")

        return [
            appSupportURL.appendingPathComponent("default.store"),
            containerSupportURL.appendingPathComponent("default.store")
        ]
    }

    private static func modificationDate(for url: URL) -> Date {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date ?? .distantPast
    }

    private static func copyStoreFiles(from sourceStoreURL: URL, to targetStoreURL: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = URL(fileURLWithPath: sourceStoreURL.path + suffix)
            let targetURL = URL(fileURLWithPath: targetStoreURL.path + suffix)

            guard FileManager.default.fileExists(atPath: sourceURL.path),
                  !FileManager.default.fileExists(atPath: targetURL.path) else {
                continue
            }

            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        }
    }

    private static func copyExternalDataDirectoryIfNeeded(from sourceStoreURL: URL, to targetStoreURL: URL) throws {
        let sourceSupportURL = externalDataDirectory(for: sourceStoreURL)
        let targetSupportURL = externalDataDirectory(for: targetStoreURL)

        guard FileManager.default.fileExists(atPath: sourceSupportURL.path),
              !FileManager.default.fileExists(atPath: targetSupportURL.path) else {
            return
        }

        try FileManager.default.copyItem(at: sourceSupportURL, to: targetSupportURL)
    }

    @discardableResult
    static func quarantineStoreFiles(at storeURL: URL) throws -> URL? {
        let fileManager = FileManager.default
        let storeFiles = [
            storeURL,
            URL(fileURLWithPath: storeURL.path + "-wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
            externalDataDirectory(for: storeURL),
        ]
        .filter { fileManager.fileExists(atPath: $0.path) }

        guard !storeFiles.isEmpty else {
            return nil
        }

        let recoveryRootURL = storeURL
            .deletingLastPathComponent()
            .appendingPathComponent("Recovery", isDirectory: true)
        let recoveryURL = recoveryRootURL
            .appendingPathComponent("ClipboardHistory-\(UUID().uuidString)", isDirectory: true)

        try fileManager.createDirectory(
            at: recoveryURL,
            withIntermediateDirectories: true
        )

        for sourceURL in storeFiles {
            let destinationURL = recoveryURL.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
        }

        return recoveryURL
    }

    private static func externalDataDirectory(for storeURL: URL) -> URL {
        let storeBaseName = storeURL.deletingPathExtension().lastPathComponent
        return storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(storeBaseName)_SUPPORT", isDirectory: true)
    }
}
