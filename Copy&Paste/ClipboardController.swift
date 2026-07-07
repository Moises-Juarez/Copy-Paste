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

@MainActor
final class ClipboardController: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var isMonitoring = false
    @Published var errorMessage: String?

    private let modelContext: ModelContext
    private let monitor = ClipboardMonitor()

    init(modelContainer: ModelContainer, startsMonitoring: Bool = true) {
        self.modelContext = ModelContext(modelContainer)
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
            save()
            return
        }

        modelContext.insert(ClipboardItem(content: text, alternateImage: alternateImage))
        save()
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
        save()
        return true
    }

    @discardableResult
    func copyPlainTextToPasteboard(_ item: ClipboardItem) -> Bool {
        copyToPasteboard(item, mode: .plainText)
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        save()
    }

    func setAlias(_ alias: String, for item: ClipboardItem) {
        let normalizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        item.alias = normalizedAlias.isEmpty ? nil : normalizedAlias
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

    func refresh() {
        do {
            let descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.copiedAt, order: .reverse)]
            )
            items = try modelContext.fetch(descriptor)
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo leer el historial: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try modelContext.save()
            refresh()
        } catch {
            errorMessage = "No se pudo guardar el historial: \(error.localizedDescription)"
        }
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

        if let existingItem = items.first(where: { $0.kind == .image && $0.imageData == data }) {
            existingItem.imageWidth = width
            existingItem.imageHeight = height
            existingItem.copiedAt = .now
            save()
            return
        }

        modelContext.insert(ClipboardItem(
            imageData: data,
            imageWidth: width,
            imageHeight: height
        ))
        save()
    }

    private func storeClipboardFiles(_ fileURLs: [URL]) {
        let fileContent = ClipboardItem.fileContent(from: fileURLs)
        guard !fileContent.isEmpty else {
            return
        }

        if let existingItem = items.first(where: { $0.kind == .file && $0.content == fileContent }) {
            existingItem.copiedAt = .now
            save()
            return
        }

        modelContext.insert(ClipboardItem(fileURLs: fileURLs))
        save()
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
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
