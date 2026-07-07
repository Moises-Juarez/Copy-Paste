//
//  HistoryWindowController.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftData
import SwiftUI

@MainActor
final class HistoryWindowController: ObservableObject {
    @Published var errorMessage: String?

    private let clipboardController: ClipboardController
    private let accessibilityPermissionController: AccessibilityPermissionController
    private let modelContainer: ModelContainer
    private var targetApplication: NSRunningApplication?
    private var window: NSWindow?

    init(
        clipboardController: ClipboardController,
        accessibilityPermissionController: AccessibilityPermissionController,
        modelContainer: ModelContainer
    ) {
        self.clipboardController = clipboardController
        self.accessibilityPermissionController = accessibilityPermissionController
        self.modelContainer = modelContainer
    }

    func show() {
        captureTargetApplication()
        clipboardController.refresh()
        accessibilityPermissionController.refresh()

        if window == nil {
            window = makeWindow()
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func pasteAndClose(_ item: ClipboardItem) {
        pasteAndClose(item, mode: .automatic)
    }

    func pasteAndClose(_ item: ClipboardItem, mode: ClipboardPasteMode) {
        guard clipboardController.copyToPasteboard(item, mode: mode) else {
            return
        }

        accessibilityPermissionController.prepareForAutomaticPaste()
        pasteIntoTargetApplication()
    }

    func pastePlainTextAndClose(_ item: ClipboardItem) {
        guard clipboardController.copyPlainTextToPasteboard(item) else {
            return
        }

        accessibilityPermissionController.prepareForAutomaticPaste()
        pasteIntoTargetApplication()
    }

    func close() {
        let appToRestore = targetApplication
        targetApplication = nil
        window?.orderOut(nil)
        NSApp.hide(nil)
        Self.activateTargetApplication(appToRestore)
    }

    private func makeWindow() -> NSWindow {
        let rootView = ContentView()
            .environmentObject(clipboardController)
            .environmentObject(accessibilityPermissionController)
            .environmentObject(self)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: rootView)
        let window = HistoryWindow(contentViewController: hostingController)
        window.title = "Historial"
        window.setContentSize(NSSize(width: 540, height: 620))
        window.minSize = NSSize(width: 420, height: 420)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in
            Task { @MainActor [weak self] in
                self?.close()
            }
        }
        window.center()
        return window
    }

    private func captureTargetApplication() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        targetApplication = frontmostApplication
    }

    private func pasteIntoTargetApplication() {
        let appToRestore = targetApplication

        window?.orderOut(nil)
        NSApp.hide(nil)
        Self.activateTargetApplication(appToRestore)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Self.activateTargetApplication(appToRestore)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if Self.sendPasteCommandWithAppleScript(to: appToRestore) {
                    return
                }

                _ = Self.sendPasteCommandWithEvents(to: appToRestore)
            }
        }
    }

    private static func activateTargetApplication(_ application: NSRunningApplication?) {
        guard let application else {
            return
        }

        application.unhide()
        application.activate(options: [.activateAllWindows])

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }

    private static func sendPasteCommandWithAppleScript(to application: NSRunningApplication?) -> Bool {
        if let application, sendPasteCommandWithAppleScript(toProcessIdentifier: application.processIdentifier) {
            return true
        }

        return sendPasteCommandWithAppleScript()
    }

    private static func sendPasteCommandWithAppleScript() -> Bool {
        let scriptSource = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: scriptSource)?.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    private static func sendPasteCommandWithAppleScript(toProcessIdentifier processIdentifier: pid_t) -> Bool {
        let scriptSource = """
        tell application "System Events"
            set targetProcess to first process whose unix id is \(processIdentifier)
            set frontmost of targetProcess to true
            tell targetProcess
                keystroke "v" using command down
            end tell
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: scriptSource)?.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    private static func sendPasteCommandWithEvents(to application: NSRunningApplication?) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0

        let pasteKey = CGKeyCode(kVK_ANSI_V)
        let pasteDown = CGEvent(keyboardEventSource: source, virtualKey: pasteKey, keyDown: true)
        let pasteUp = CGEvent(keyboardEventSource: source, virtualKey: pasteKey, keyDown: false)

        pasteDown?.flags = .maskCommand
        pasteUp?.flags = .maskCommand

        guard let pasteDown, let pasteUp else {
            return false
        }

        if let application {
            pasteDown.postToPid(application.processIdentifier)
            pasteUp.postToPid(application.processIdentifier)
            return true
        }

        [pasteDown, pasteUp].forEach { event in
            event?.post(tap: .cghidEventTap)
        }
        return true
    }
}

private final class HistoryWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        guard handleEscape() else {
            super.cancelOperation(sender)
            return
        }
    }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == UInt16(kVK_Escape), handleEscape() else {
            super.keyDown(with: event)
            return
        }
    }

    private func handleEscape() -> Bool {
        guard attachedSheet == nil else {
            return false
        }

        onEscape?()
        return true
    }
}
