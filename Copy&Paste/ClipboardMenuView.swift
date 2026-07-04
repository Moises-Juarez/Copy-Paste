//
//  ClipboardMenuView.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import SwiftUI

struct ClipboardMenuView: View {
    @EnvironmentObject private var clipboardController: ClipboardController
    @EnvironmentObject private var accessibilityPermissionController: AccessibilityPermissionController
    @EnvironmentObject private var globalHotKeyController: GlobalHotKeyController
    @EnvironmentObject private var historyWindowController: HistoryWindowController
    @EnvironmentObject private var launchAtLoginController: LaunchAtLoginController

    private var pinnedItems: [ClipboardItem] {
        clipboardController.items.filter(\.isPinned)
    }

    private var recentItems: [ClipboardItem] {
        clipboardController.items.filter { !$0.isPinned }
    }

    var body: some View {
        Button {
            showHistoryWindow()
        } label: {
            Label("Mostrar historial", systemImage: "rectangle.stack")
        }
        .keyboardShortcut("v", modifiers: [.command, .shift])

        Button {
            clipboardController.captureCurrentPasteboard()
        } label: {
            Label("Capturar ahora", systemImage: "arrow.clockwise")
        }

        Toggle(isOn: Binding(
            get: { launchAtLoginController.isEnabled },
            set: { launchAtLoginController.setEnabled($0) }
        )) {
            Label("Iniciar con macOS", systemImage: "power")
        }

        if launchAtLoginController.requiresApproval {
            Button {
                launchAtLoginController.openLoginItemsSettings()
            } label: {
                Label("Aprobar en Ajustes", systemImage: "gear")
            }
        }

        if !accessibilityPermissionController.isTrusted {
            Button {
                accessibilityPermissionController.requestPermissionAndOpenSettings()
            } label: {
                Label("Permitir pegado automático", systemImage: "hand.raised")
            }
        }

        Divider()

        if clipboardController.items.isEmpty {
            Text("Sin copiados")
        } else {
            clipboardSection(title: "Fijos", items: Array(pinnedItems.prefix(6)), pinned: true)
            clipboardSection(title: "Recientes", items: Array(recentItems.prefix(8)), pinned: false)
        }

        if !clipboardController.items.isEmpty {
            Divider()

            Button(role: .destructive) {
                clipboardController.clearHistory()
            } label: {
                Label("Limpiar historial", systemImage: "trash")
            }
            .disabled(recentItems.isEmpty)
        }

        if let errorMessage = clipboardController.errorMessage ?? launchAtLoginController.errorMessage ?? globalHotKeyController.errorMessage ?? historyWindowController.errorMessage {
            Divider()
            Text(errorMessage)
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Salir", systemImage: "power.circle")
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private func clipboardSection(title: String, items: [ClipboardItem], pinned: Bool) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { item in
                    Button {
                        clipboardController.copyToPasteboard(item)
                    } label: {
                        Label(menuTitle(for: item), systemImage: systemImage(for: item, pinned: pinned))
                    }
                }
            }
        }
    }

    private func showHistoryWindow() {
        historyWindowController.show()
    }

    private func menuTitle(for item: ClipboardItem) -> String {
        let preview = item.menuTitle

        guard preview.count > 60 else {
            return preview.isEmpty ? "Texto sin vista previa" : preview
        }

        return "\(preview.prefix(57))..."
    }

    private func systemImage(for item: ClipboardItem, pinned: Bool) -> String {
        if pinned {
            return "pin.fill"
        }

        return item.isImage ? "photo" : "doc.on.doc"
    }
}
