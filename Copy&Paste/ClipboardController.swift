//
//  ClipboardController.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import Combine
import Foundation
import SwiftData

struct ClipboardFileMetadata: Equatable, Sendable {
    let representedBytes: Int64
    let unavailableFileCount: Int
}

private struct ClipboardFileMetadataSnapshot: Sendable {
    let id: UUID
    let fileURLs: [URL]
}

@MainActor
final class ClipboardController: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var estimatedStorageBytes: Int64 = 0
    @Published private(set) var unavailableFileItemCount = 0
    @Published var errorMessage: String?

    let retentionSettings: HistoryRetentionSettings

    private let modelContext: ModelContext
    private let monitor = ClipboardMonitor()
    private var fileMetadataByItemID: [UUID: ClipboardFileMetadata] = [:]
    private var fileMetadataRefreshTask: Task<Void, Never>?
    private var deferredSaveTask: Task<Void, Never>?

    init(
        modelContainer: ModelContainer,
        startsMonitoring: Bool = true,
        retentionSettings: HistoryRetentionSettings
    ) {
        self.modelContext = ModelContext(modelContainer)
        self.retentionSettings = retentionSettings
        refresh()

        if startsMonitoring {
            startMonitoring()
        }
    }

    func startMonitoring() {
        monitor.start { [weak self] payload in
            self?.storeClipboardPayload(payload)
        }
        isMonitoring = monitor.isRunning
    }

    func captureCurrentPasteboard() {
        guard let payload = ClipboardMonitor.currentPayload() else {
            return
        }

        storeClipboardPayload(payload)
        monitor.noteCurrentPasteboardContent(payload)
    }

    func fileMetadata(for item: ClipboardItem) -> ClipboardFileMetadata? {
        fileMetadataByItemID[item.id]
    }

    func refreshFileMetadata() {
        let snapshots = items.compactMap { item -> ClipboardFileMetadataSnapshot? in
            guard item.isFile else {
                return nil
            }

            return ClipboardFileMetadataSnapshot(id: item.id, fileURLs: item.fileURLs)
        }

        fileMetadataRefreshTask?.cancel()

        guard !snapshots.isEmpty else {
            fileMetadataByItemID = [:]
            unavailableFileItemCount = 0
            return
        }

        fileMetadataRefreshTask = Task { [weak self] in
            let metadata = await Task.detached(priority: .utility) {
                Self.loadFileMetadata(from: snapshots)
            }.value

            guard !Task.isCancelled, let self else {
                return
            }

            fileMetadataByItemID = metadata
            unavailableFileItemCount = metadata.values.filter {
                $0.unavailableFileCount > 0
            }.count
        }
    }

    func storeClipboardText(_ text: String, alternateImage: ClipboardImagePayload? = nil) {
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else {
            return
        }

        if let existingItem = items.first(where: { $0.kind == .text && normalized($0.content) == normalizedText }) {
            existingItem.content = text
            existingItem.imageData = alternateImage?.data
            existingItem.imageWidth = alternateImage?.width
            existingItem.imageHeight = alternateImage?.height
            existingItem.copiedAt = .now
            existingItem.invalidateVisualCache()
            existingItem.refreshStoredByteCount()
            save(enforceRetentionPolicy: true)
            return
        }

        modelContext.insert(ClipboardItem(content: text, alternateImage: alternateImage))
        save(enforceRetentionPolicy: true)
    }

    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) -> Bool {
        copyToPasteboard(item, mode: .automatic)
    }

    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem, mode: ClipboardPasteMode) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch mode {
        case .automatic:
            guard copyAutomatic(item) else {
                return false
            }
        case .table:
            guard copyTableText(item) else {
                return false
            }
        case .plainText:
            guard copyPlainText(item) else {
                return false
            }
        case .image:
            guard copyImage(item) else {
                return false
            }
        }

        errorMessage = nil
        item.copiedAt = .now
        promoteAfterUse(item)
        scheduleDeferredSave()
        return true
    }

    @discardableResult
    func copyPlainTextToPasteboard(_ item: ClipboardItem) -> Bool {
        copyToPasteboard(item, mode: .plainText)
    }

    func togglePin(_ item: ClipboardItem) {
        if item.isPinned {
            item.isPinned = false
            item.pinnedPosition = nil
            updatePinnedPositions(orderedPinnedItems(from: items))
        } else {
            let currentPinnedItems = orderedPinnedItems(from: items)
            item.isPinned = true
            item.pinnedPosition = 0

            for (index, pinnedItem) in currentPinnedItems.enumerated() {
                pinnedItem.pinnedPosition = index + 1
            }
        }

        save()
    }

    func orderedPinnedItems(from source: [ClipboardItem]) -> [ClipboardItem] {
        source
            .filter(\.isPinned)
            .sorted { first, second in
                switch (first.pinnedPosition, second.pinnedPosition) {
                case let (firstPosition?, secondPosition?) where firstPosition != secondPosition:
                    return firstPosition < secondPosition
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return first.copiedAt > second.copiedAt
                }
            }
    }

    func setPinnedOrder(_ orderedItems: [ClipboardItem]) {
        let currentPinnedItems = orderedPinnedItems(from: items)
        let currentIDs = Set(currentPinnedItems.map(\.id))
        let orderedIDs = Set(orderedItems.map(\.id))

        guard currentIDs == orderedIDs else {
            return
        }

        updatePinnedPositions(orderedItems)
        save()
    }

    func setAlias(_ alias: String, for item: ClipboardItem) {
        let normalizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        item.alias = normalizedAlias.isEmpty ? nil : normalizedAlias
        item.refreshStoredByteCount()
        save()
    }

    func delete(_ item: ClipboardItem) {
        modelContext.delete(item)
        save()
    }

    func clearHistory() {
        for item in items where !item.isPinned {
            modelContext.delete(item)
        }
        save()
    }

    func cleanUnavailableFileReferences() {
        for item in items where item.isFile && item.hasUnavailableFiles {
            let existingFileURLs = item.existingFileURLs

            if existingFileURLs.isEmpty {
                modelContext.delete(item)
            } else {
                item.content = ClipboardItem.fileContent(from: existingFileURLs)
                item.invalidateVisualCache()
                item.refreshStoredByteCount()
            }
        }

        save()
        refreshFileMetadata()
    }

    func enforceRetentionPolicy() {
        do {
            if try pruneHistoryIfNeeded() {
                try modelContext.save()
            }

            refresh()
        } catch {
            errorMessage = "No se pudo aplicar la configuracion del historial: \(error.localizedDescription)"
        }
    }

    func refresh() {
        do {
            let descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
            )
            items = try modelContext.fetch(descriptor)
            refreshInMemoryStatistics()
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo leer el historial: \(error.localizedDescription)"
        }
    }

    private func save(
        enforceRetentionPolicy: Bool = false,
        refreshItems: Bool = true
    ) {
        do {
            try modelContext.save()
            if enforceRetentionPolicy, try pruneHistoryIfNeeded() {
                try modelContext.save()
            }

            if refreshItems {
                refresh()
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "No se pudo guardar el historial: \(error.localizedDescription)"
        }
    }

    private func updatePinnedPositions(_ orderedItems: [ClipboardItem]) {
        for (index, item) in orderedItems.enumerated() {
            item.pinnedPosition = index
        }
    }

    private func promoteAfterUse(_ item: ClipboardItem) {
        items = items.sorted { first, second in
            if first.id == second.id {
                return false
            }

            if first.id == item.id {
                return true
            }

            if second.id == item.id {
                return false
            }

            return first.copiedAt > second.copiedAt
        }
    }

    private func scheduleDeferredSave() {
        deferredSaveTask?.cancel()
        deferredSaveTask = Task { [weak self] in
            await Task.yield()

            guard !Task.isCancelled else {
                return
            }

            self?.save(refreshItems: false)
        }
    }

    private func refreshInMemoryStatistics() {
        estimatedStorageBytes = items.reduce(into: Int64(0)) { total, item in
            total += item.knownStorageBytes
        }

        let currentItemIDs = Set(items.map(\.id))
        fileMetadataByItemID = fileMetadataByItemID.filter {
            currentItemIDs.contains($0.key)
        }
        unavailableFileItemCount = fileMetadataByItemID.values.filter {
            $0.unavailableFileCount > 0
        }.count
    }

    private func pruneHistoryIfNeeded() throws -> Bool {
        let descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
        )
        let currentItems = try modelContext.fetch(descriptor)
        let cutoffDate = retentionSettings.retentionCutoffDate
        var keptUnpinnedCount = 0
        var keptStorageBytes = currentItems
            .filter(\.isPinned)
            .reduce(into: Int64(0)) { total, item in
                total += item.knownStorageBytes
            }
        var didPrune = false

        for item in currentItems where !item.isPinned {
            let isExpired = cutoffDate.map { item.copiedAt < $0 } ?? false
            let exceedsItemLimit = keptUnpinnedCount >= retentionSettings.maxUnpinnedItems
            let itemStorageBytes = item.knownStorageBytes
            let exceedsStorageLimit = keptUnpinnedCount > 0
                && keptStorageBytes + itemStorageBytes > retentionSettings.maxStorageBytes

            if isExpired || exceedsItemLimit || exceedsStorageLimit {
                modelContext.delete(item)
                didPrune = true
                continue
            }

            keptUnpinnedCount += 1
            keptStorageBytes += itemStorageBytes
        }

        return didPrune
    }

    private func storeClipboardPayload(_ payload: ClipboardPayload) {
        switch payload {
        case .text(let text, let alternateImage):
            storeClipboardText(text, alternateImage: alternateImage)
        case .image(let image):
            storeClipboardImage(image.data, width: image.width, height: image.height)
        case .files(let files):
            storeClipboardFiles(files.fileURLs)
        }
    }

    private func storeClipboardImage(_ data: Data, width: Double?, height: Double?) {
        guard !data.isEmpty else {
            return
        }

        if let existingItem = items.first(where: {
            $0.kind == .image
                && $0.storedByteCount == Int64(data.count)
                && $0.imageData == data
        }) {
            existingItem.imageWidth = width
            existingItem.imageHeight = height
            existingItem.copiedAt = .now
            existingItem.invalidateVisualCache()
            save(enforceRetentionPolicy: true)
            return
        }

        modelContext.insert(ClipboardItem(
            imageData: data,
            imageWidth: width,
            imageHeight: height
        ))
        save(enforceRetentionPolicy: true)
    }

    private func storeClipboardFiles(_ fileURLs: [URL]) {
        let fileContent = ClipboardItem.fileContent(from: fileURLs)
        guard !fileContent.isEmpty else {
            return
        }

        if let existingItem = items.first(where: { $0.kind == .file && $0.content == fileContent }) {
            existingItem.copiedAt = .now
            save(enforceRetentionPolicy: true)
            return
        }

        modelContext.insert(ClipboardItem(fileURLs: fileURLs))
        save(enforceRetentionPolicy: true)
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func loadFileMetadata(
        from snapshots: [ClipboardFileMetadataSnapshot]
    ) -> [UUID: ClipboardFileMetadata] {
        let fileManager = FileManager.default
        var metadataByItemID: [UUID: ClipboardFileMetadata] = [:]

        for snapshot in snapshots {
            var representedBytes: Int64 = 0
            var unavailableFileCount = 0

            for fileURL in snapshot.fileURLs {
                guard fileManager.fileExists(atPath: fileURL.path) else {
                    unavailableFileCount += 1
                    continue
                }

                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                representedBytes += (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            }

            metadataByItemID[snapshot.id] = ClipboardFileMetadata(
                representedBytes: representedBytes,
                unavailableFileCount: unavailableFileCount
            )
        }

        return metadataByItemID
    }

    private func copyAutomatic(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text:
            writeTextToPasteboard(item.content, includeTabularTypes: true)
            monitor.noteCurrentPasteboardContent(.text(item.content, alternateImage: nil))
            return true
        case .image:
            return copyImage(item)
        case .file:
            return copyFiles(item)
        }
    }

    private func copyTableText(_ item: ClipboardItem) -> Bool {
        guard item.kind == .text else {
            errorMessage = "Solo los textos pueden pegarse como tabla."
            return false
        }

        guard item.hasTabularText else {
            errorMessage = "Este texto no tiene filas o columnas para pegarse como tabla."
            return false
        }

        writeTextToPasteboard(item.content, includeTabularTypes: true)
        monitor.noteCurrentPasteboardContent(.text(item.content, alternateImage: nil))
        return true
    }

    private func copyPlainText(_ item: ClipboardItem) -> Bool {
        guard item.kind == .text else {
            errorMessage = "Solo los textos pueden pegarse sin formato."
            return false
        }

        NSPasteboard.general.setString(item.content, forType: .string)
        monitor.noteCurrentPasteboardContent(.text(item.content, alternateImage: nil))
        return true
    }

    private func copyImage(_ item: ClipboardItem) -> Bool {
        guard let imagePayload = item.alternateImagePayload else {
            errorMessage = "No se pudo copiar la imagen porque ya no esta disponible."
            return false
        }

        if let image = NSImage(data: imagePayload.data) {
            NSPasteboard.general.writeObjects([image])
        }
        NSPasteboard.general.setData(imagePayload.data, forType: ClipboardMonitor.pngPasteboardType)
        monitor.noteCurrentPasteboardContent(.image(imagePayload))
        return true
    }

    private func copyFiles(_ item: ClipboardItem) -> Bool {
        let fileURLs = item.fileURLs

        guard !fileURLs.isEmpty else {
            errorMessage = "No se pudo copiar el archivo porque ya no esta disponible."
            return false
        }

        let existingFileURLs = item.existingFileURLs
        guard existingFileURLs.count == fileURLs.count else {
            errorMessage = "Uno o mas archivos ya no estan disponibles en su ubicacion original."
            return false
        }

        let pasteboardURLs = existingFileURLs.map { $0 as NSURL }
        guard NSPasteboard.general.writeObjects(pasteboardURLs) else {
            errorMessage = "No se pudieron copiar los archivos al portapapeles."
            return false
        }

        monitor.noteCurrentPasteboardContent(.files(ClipboardFilePayload(fileURLs: existingFileURLs)))
        return true
    }

    private func writeTextToPasteboard(_ text: String, includeTabularTypes: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.setString(text, forType: .string)

        guard includeTabularTypes, ClipboardMonitor.isTabularText(text) else {
            return
        }

        for type in ClipboardMonitor.tabularTextPasteboardTypes {
            pasteboard.setString(text, forType: type)
        }
    }
}
