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

enum HistoryKeyboardCommand {
    case previous
    case next
    case pasteSelected
}

@MainActor
final class HistoryWindowController: ObservableObject {
    @Published var errorMessage: String?
    @Published private(set) var presentationID = UUID()
    let keyboardCommands = PassthroughSubject<HistoryKeyboardCommand, Never>()

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
        accessibilityPermissionController.refresh()
        clipboardController.refreshFileMetadata()

        if window == nil {
            window = makeWindow()
        }

        presentationID = UUID()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func prepareWindow() {
        guard window == nil else {
            return
        }

        window = makeWindow()
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
            .environmentObject(clipboardController.retentionSettings)
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
            self?.close()
        }
        window.onKeyboardCommand = { [weak self] command in
            self?.keyboardCommands.send(command)
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
    var onKeyboardCommand: ((HistoryKeyboardCommand) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if let command = keyboardCommand(for: event) {
            onKeyboardCommand?(command)
            return
        }

        super.sendEvent(event)
    }

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

    private func keyboardCommand(for event: NSEvent) -> HistoryKeyboardCommand? {
        guard event.type == .keyDown,
              attachedSheet == nil,
              childWindows?.isEmpty != false,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return nil
        }

        switch event.keyCode {
        case UInt16(kVK_UpArrow):
            return .previous
        case UInt16(kVK_DownArrow):
            return .next
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            return .pasteSelected
        default:
            return nil
        }
    }
}
