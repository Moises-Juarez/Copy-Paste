//
//  ClipboardMonitor.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import Combine
import Foundation

struct ClipboardImagePayload: Equatable {
    let data: Data
    let width: Double?
    let height: Double?
}

struct ClipboardFilePayload: Equatable {
    let fileURLs: [URL]
}

enum ClipboardPayload: Equatable {
    case text(String, alternateImage: ClipboardImagePayload?)
    case image(ClipboardImagePayload)
    case files(ClipboardFilePayload)
}

final class ClipboardMonitor: ObservableObject {
    @Published private(set) var isRunning = false

    static let pngPasteboardType = NSPasteboard.PasteboardType("public.png")
    static let tiffPasteboardType = NSPasteboard.PasteboardType("public.tiff")
    static let tabularTextPasteboardTypes = [
        NSPasteboard.PasteboardType("NSTabularTextPboardType"),
        NSPasteboard.PasteboardType("public.tab-separated-values-text"),
        NSPasteboard.PasteboardType("public.utf8-tab-separated-values-text")
    ]

    private static let preferredTextPasteboardTypes = tabularTextPasteboardTypes + [
        .string,
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.utf8-plain-text")
    ]

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var lastCapturedPayload: ClipboardPayload?
    private var timer: Timer?
    private var onChange: ((ClipboardPayload) -> Void)?

    init() {
        self.lastChangeCount = pasteboard.changeCount
    }

    deinit {
        stop()
    }

    func start(onChange: @escaping (ClipboardPayload) -> Void) {
        self.onChange = onChange

        guard !isRunning else {
            return
        }

        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.captureIfNeeded()
        }
        timer?.tolerance = 0.2
        isRunning = true
        captureCurrentPayload()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        onChange = nil
    }

    func noteCurrentPasteboardContent(_ payload: ClipboardPayload) {
        lastChangeCount = pasteboard.changeCount
        lastCapturedPayload = normalized(payload)
    }

    static func currentPayload(from pasteboard: NSPasteboard = .general) -> ClipboardPayload? {
        if let filePayload = filePayload(from: pasteboard) {
            return .files(filePayload)
        }

        if let tablePayload = tabularTextPayload(from: pasteboard) {
            return tablePayload
        }

        if let imagePayload = imagePayload(from: pasteboard) {
            return .image(imagePayload)
        }

        return textPayload(from: pasteboard)
    }

    static func isTabularText(_ text: String) -> Bool {
        let nonEmptyLineCount = text
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        return text.contains("\t") || nonEmptyLineCount > 1
    }

    private func captureIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        guard let payload = Self.currentPayload(from: pasteboard) else {
            return
        }

        capture(payload)
    }

    private func captureCurrentPayload() {
        guard let payload = Self.currentPayload(from: pasteboard) else {
            return
        }

        capture(payload)
    }

    private func capture(_ payload: ClipboardPayload) {
        guard let normalizedPayload = normalized(payload), normalizedPayload != lastCapturedPayload else {
            return
        }

        lastCapturedPayload = normalizedPayload
        onChange?(payload)
    }

    private static func tabularTextPayload(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        guard let text = text(from: pasteboard) else {
            return nil
        }

        guard hasTabularHints(in: pasteboard) || isTabularText(text) else {
            return nil
        }

        return .text(text, alternateImage: imagePayload(from: pasteboard))
    }

    private static func textPayload(from pasteboard: NSPasteboard) -> ClipboardPayload? {
        guard let text = text(from: pasteboard) else {
            return nil
        }

        return .text(text, alternateImage: nil)
    }

    private static func text(from pasteboard: NSPasteboard) -> String? {
        for type in preferredTextPasteboardTypes {
            guard let text = pasteboard.string(forType: type),
                  !normalized(text).isEmpty else {
                continue
            }

            return text
        }

        return nil
    }

    private static func hasTabularHints(in pasteboard: NSPasteboard) -> Bool {
        let pasteboardTypeNames = pasteboard.types?.map { $0.rawValue.lowercased() } ?? []
        return pasteboardTypeNames.contains { typeName in
            typeName.contains("excel")
                || typeName.contains("spreadsheet")
                || typeName.contains("tabular")
                || typeName.contains("tab-separated")
        }
    }

    private static func filePayload(from pasteboard: NSPasteboard) -> ClipboardFilePayload? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard
            .readObjects(forClasses: [NSURL.self], options: options)?
            .compactMap { object -> URL? in
                if let url = object as? URL {
                    return url
                }

                if let url = object as? NSURL {
                    return url as URL
                }

                return nil
            } ?? []
        let fileURLs = normalizedFileURLs(urls)

        guard !fileURLs.isEmpty else {
            return nil
        }

        return ClipboardFilePayload(fileURLs: fileURLs)
    }

    private static func imagePayload(from pasteboard: NSPasteboard) -> ClipboardImagePayload? {
        if let pngData = pasteboard.data(forType: pngPasteboardType), !pngData.isEmpty {
            return imagePayload(fromPNGData: pngData)
        }

        if let tiffData = pasteboard.data(forType: tiffPasteboardType),
           let pngData = pngData(fromImageData: tiffData) {
            return imagePayload(fromPNGData: pngData)
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let pngData = pngData(from: image) else {
            return nil
        }

        return imagePayload(fromPNGData: pngData)
    }

    private static func imagePayload(fromPNGData data: Data) -> ClipboardImagePayload {
        let size = imageSize(from: data)
        return ClipboardImagePayload(
            data: data,
            width: size.map { Double($0.width) },
            height: size.map { Double($0.height) }
        )
    }

    private static func pngData(fromImageData data: Data) -> Data? {
        guard let image = NSImage(data: data) else {
            return nil
        }

        return pngData(from: image)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffRepresentation = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func imageSize(from data: Data) -> CGSize? {
        if let bitmap = NSBitmapImageRep(data: data) {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        return NSImage(data: data)?.size
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedFileURLs(_ urls: [URL]) -> [URL] {
        var seenPaths = Set<String>()

        return urls.compactMap { url in
            guard url.isFileURL else {
                return nil
            }

            let standardizedURL = url.standardizedFileURL
            let path = standardizedURL.path

            guard FileManager.default.fileExists(atPath: path),
                  seenPaths.insert(path).inserted else {
                return nil
            }

            return standardizedURL
        }
    }

    private func normalized(_ payload: ClipboardPayload) -> ClipboardPayload? {
        switch payload {
        case .text(let text, let alternateImage):
            let normalizedText = normalized(text)
            guard !normalizedText.isEmpty else {
                return nil
            }

            let normalizedAlternateImage = alternateImage.flatMap { image in
                image.data.isEmpty ? nil : image
            }
            return .text(normalizedText, alternateImage: normalizedAlternateImage)
        case .image(let image):
            return image.data.isEmpty ? nil : .image(image)
        case .files(let files):
            let fileURLs = Self.normalizedFileURLs(files.fileURLs)
            return fileURLs.isEmpty ? nil : .files(ClipboardFilePayload(fileURLs: fileURLs))
        }
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
