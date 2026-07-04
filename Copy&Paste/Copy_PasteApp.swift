//
//  Copy_PasteApp.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import Foundation
import SwiftUI
import SwiftData

@main
struct Copy_PasteApp: App {
    private let globalHotKeyController: GlobalHotKeyController

    @StateObject private var clipboardController: ClipboardController
    @StateObject private var accessibilityPermissionController: AccessibilityPermissionController
    @StateObject private var historyWindowController: HistoryWindowController
    @StateObject private var launchAtLoginController = LaunchAtLoginController()

    init() {
        let modelContainer = Self.makeModelContainer()
        let clipboardController = ClipboardController(modelContainer: modelContainer)
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

        self.globalHotKeyController = globalHotKeyController
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
        } label: {
            Label("Copy&Paste", systemImage: "doc.on.clipboard")
        }
        .menuBarExtraStyle(.menu)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            ClipboardItem.self,
        ])

        do {
            let storeURL = try clipboardHistoryStoreURL()
            try migrateDefaultStoreIfNeeded(to: storeURL)

            let modelConfiguration = ModelConfiguration(
                "ClipboardHistory",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )

            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
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
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .max { lhs, rhs in
                modificationDate(for: lhs) < modificationDate(for: rhs)
            }
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

    private static func externalDataDirectory(for storeURL: URL) -> URL {
        let storeBaseName = storeURL.deletingPathExtension().lastPathComponent
        return storeURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(storeBaseName)_SUPPORT", isDirectory: true)
    }
}
