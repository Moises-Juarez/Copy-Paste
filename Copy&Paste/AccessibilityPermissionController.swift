//
//  AccessibilityPermissionController.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AccessibilityPermissionController: ObservableObject {
    @Published private(set) var isTrusted: Bool
    @Published private(set) var guidanceMessage: String?

    private var didRequestSystemPrompt = false
    private var statusTimer: Timer?

    init() {
        self.isTrusted = Self.hasPasteAutomationAccess
    }

    deinit {
        statusTimer?.invalidate()
    }

    func refresh() {
        isTrusted = Self.hasPasteAutomationAccess

        if isTrusted {
            guidanceMessage = nil
            didRequestSystemPrompt = false
            stopStatusPolling()
        }
    }

    func prepareForAutomaticPaste() {
        refresh()

        guard !isTrusted else {
            return
        }

        if requestSystemPromptIfNeeded() {
            refresh()
            return
        }

        refresh()

        guard !isTrusted else {
            return
        }

        guidanceMessage = "El texto ya quedó copiado. Si el pegado automatico no ocurre, revisa que Copy&Paste siga activo en Accesibilidad."
        startStatusPolling()
    }

    func requestPermissionAndOpenSettings() {
        refresh()

        guard !isTrusted else {
            return
        }

        _ = requestSystemPromptIfNeeded()
        guidanceMessage = "Activa Copy&Paste en Accesibilidad para permitir el pegado automático."
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let settingsURL = URL(string: Self.accessibilitySettingsURLString) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
        startStatusPolling()
    }

    func clearGuidanceMessage() {
        guidanceMessage = nil
    }

    private func requestSystemPromptIfNeeded() -> Bool {
        guard !didRequestSystemPrompt else {
            return Self.hasPasteAutomationAccess
        }

        didRequestSystemPrompt = true
        return CGRequestPostEventAccess() || Self.hasPasteAutomationAccess
    }

    private func startStatusPolling() {
        guard statusTimer == nil else {
            return
        }

        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let controller = self else {
                return
            }

            Task { @MainActor in
                controller.refresh()
            }
        }
    }

    private func stopStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = nil
    }

    private static var hasPasteAutomationAccess: Bool {
        CGPreflightPostEventAccess() || AXIsProcessTrusted()
    }

    private static let accessibilitySettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
}
