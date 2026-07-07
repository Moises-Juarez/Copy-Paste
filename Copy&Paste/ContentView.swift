//
//  ContentView.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var clipboardController: ClipboardController
    @EnvironmentObject private var accessibilityPermissionController: AccessibilityPermissionController
    @EnvironmentObject private var historyWindowController: HistoryWindowController

    @State private var searchText = ""
    @State private var aliasEditorItem: ClipboardItem?
    @State private var aliasText = ""
    @State private var isShowingAliasEditor = false
    @State private var isShowingClearHistoryConfirmation = false

    private var items: [ClipboardItem] {
        clipboardController.items
    }

    private var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return items
        }

        return items.filter { item in
            item.matchesSearch(query)
        }
    }

    private var pinnedItems: [ClipboardItem] {
        filteredItems.filter(\.isPinned)
    }

    private var historyItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }

    private var allHistoryItems: [ClipboardItem] {
        items.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HistoryControlsBar(
                    isMonitoring: clipboardController.isMonitoring,
                    accessibilityPermissionController: accessibilityPermissionController,
                    canClearHistory: !allHistoryItems.isEmpty,
                    onCapture: captureCurrentPasteboard,
                    onClearHistory: requestClearHistoryConfirmation
                )

                Divider()

                List {
                    if !pinnedItems.isEmpty {
                        Section("Fijos") {
                            ForEach(pinnedItems) { item in
                                clipboardRow(for: item)
                            }
                            .onDelete { offsets in
                                deleteItems(at: offsets, from: pinnedItems)
                            }
                        }
                    }

                    if !historyItems.isEmpty {
                        Section("Historial") {
                            ForEach(historyItems) { item in
                                clipboardRow(for: item)
                            }
                            .onDelete { offsets in
                                deleteItems(at: offsets, from: historyItems)
                            }
                        }
                    }
                }
                .overlay {
                    if items.isEmpty {
                        ContentUnavailableView(
                            "Sin copiados",
                            systemImage: "doc.on.clipboard",
                            description: Text("Copia texto, una captura o archivos para verlos aqui.")
                        )
                    } else if filteredItems.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .navigationTitle("Copiados")
            .searchable(text: $searchText, prompt: "Buscar")
        }
        .sheet(isPresented: $isShowingAliasEditor) {
            if let aliasEditorItem {
                AliasEditorView(
                    item: aliasEditorItem,
                    aliasText: $aliasText,
                    onCancel: closeAliasEditor,
                    onSave: saveAlias
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = footerMessage {
                ContentUnavailableView(
                    message,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .padding(.horizontal)
            }
        }
        .confirmationDialog(
            "Eliminar historial",
            isPresented: $isShowingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar historial", role: .destructive, action: clearHistory)
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se eliminaran todos los registros no fijados. Los registros fijados se conservaran.")
        }
    }

    private var footerMessage: String? {
        historyWindowController.errorMessage
            ?? clipboardController.errorMessage
    }

    @ViewBuilder
    private func clipboardRow(for item: ClipboardItem) -> some View {
        ClipboardRow(
            item: item,
            onPaste: {
                pasteAndClose(item)
            },
            onPasteMode: { mode in
                pasteAndClose(item, mode: mode)
            },
            onTogglePin: {
                togglePin(item)
            },
            onDelete: {
                delete(item)
            },
            onEditAlias: {
                openAliasEditor(for: item)
            }
        )
        .contextMenu {
            ForEach(item.availablePasteModes) { mode in
                Button {
                    pasteAndClose(item, mode: mode)
                } label: {
                    Label(mode.title, systemImage: mode.systemImage)
                }
            }

            Divider()

            Button {
                togglePin(item)
            } label: {
                Label(item.isPinned ? "Quitar fijo" : "Fijar", systemImage: item.isPinned ? "pin.slash" : "pin")
            }

            if item.isPinned || item.displayAlias != nil {
                Button {
                    openAliasEditor(for: item)
                } label: {
                    Label("Editar alias", systemImage: "tag")
                }
            }

            Button(role: .destructive) {
                delete(item)
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        }
    }

    private func captureCurrentPasteboard() {
        clipboardController.captureCurrentPasteboard()
    }

    private func pasteAndClose(_ item: ClipboardItem) {
        historyWindowController.pasteAndClose(item)
    }

    private func pasteAndClose(_ item: ClipboardItem, mode: ClipboardPasteMode) {
        historyWindowController.pasteAndClose(item, mode: mode)
    }

    private func togglePin(_ item: ClipboardItem) {
        let wasPinned = item.isPinned

        withAnimation {
            clipboardController.togglePin(item)
        }

        if !wasPinned {
            openAliasEditor(for: item)
        }
    }

    private func delete(_ item: ClipboardItem) {
        withAnimation {
            clipboardController.delete(item)
        }
    }

    private func deleteItems(at offsets: IndexSet, from source: [ClipboardItem]) {
        withAnimation {
            for offset in offsets {
                delete(source[offset])
            }
        }
    }

    private func requestClearHistoryConfirmation() {
        isShowingClearHistoryConfirmation = true
    }

    private func clearHistory() {
        withAnimation {
            clipboardController.clearHistory()
        }
    }

    private func openAliasEditor(for item: ClipboardItem) {
        aliasEditorItem = item
        aliasText = item.displayAlias ?? ""
        isShowingAliasEditor = true
    }

    private func closeAliasEditor() {
        isShowingAliasEditor = false
        aliasEditorItem = nil
        aliasText = ""
    }

    private func saveAlias() {
        guard let aliasEditorItem else {
            closeAliasEditor()
            return
        }

        clipboardController.setAlias(aliasText, for: aliasEditorItem)
        closeAliasEditor()
    }
}

private struct HistoryControlsBar: View {
    let isMonitoring: Bool
    @ObservedObject var accessibilityPermissionController: AccessibilityPermissionController
    let canClearHistory: Bool
    let onCapture: () -> Void
    let onClearHistory: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MonitorStatusView(isRunning: isMonitoring)
                .padding(.leading, 4)

            AccessibilityStatusButton(controller: accessibilityPermissionController)

            Spacer(minLength: 12)

            Button(action: onCapture) {
                Label("Capturar", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button(role: .destructive, action: onClearHistory) {
                Label("Limpiar", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(!canClearHistory)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let onPaste: () -> Void
    let onPasteMode: (ClipboardPasteMode) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onEditAlias: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onPaste) {
                HStack(alignment: .top, spacing: 10) {
                    itemPreview

                    VStack(alignment: .leading, spacing: 4) {
                        if let displayAlias = item.displayAlias {
                            Text(displayAlias)
                                .font(.headline)
                                .lineLimit(1)
                        }

                        Text(item.preview.isEmpty ? "Texto sin vista previa" : item.preview)
                            .font(item.displayAlias == nil ? .body : .subheadline)
                            .foregroundStyle(item.displayAlias == nil ? .primary : .secondary)
                            .lineLimit(item.displayAlias == nil ? 2 : 1)

                        if item.isFile {
                            Text(item.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(item.copiedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.availablePasteModes.count > 1 {
                Menu {
                    ForEach(item.availablePasteModes) { mode in
                        Button {
                            onPasteMode(mode)
                        } label: {
                            Label(mode.title, systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Seleccionar modo de pegado")
            }

            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
            }
            .buttonStyle(.borderless)
            .help(item.isPinned ? "Quitar fijo" : "Fijar")

            if item.isPinned || item.displayAlias != nil {
                Button(action: onEditAlias) {
                    Image(systemName: "tag")
                }
                .buttonStyle(.borderless)
                .help(item.displayAlias == nil ? "Agregar alias" : "Editar alias")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Eliminar")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var itemPreview: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                }
        } else if item.isFile, let fileIcon = item.fileIcon {
            Image(nsImage: fileIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 34)
        } else {
            Image(systemName: item.isPinned ? "pin.fill" : item.isFile ? "doc" : "doc.text")
                .foregroundStyle(item.isPinned ? .blue : .secondary)
                .frame(width: 48, height: 34)
        }
    }
}

private struct AliasEditorView: View {
    let item: ClipboardItem
    @Binding var aliasText: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Alias del fijo", systemImage: "tag")
                .font(.headline)

            Text(item.preview.isEmpty ? "Texto sin vista previa" : item.preview)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            TextField("Alias", text: $aliasText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSave)

            HStack {
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Quitar alias") {
                    aliasText = ""
                    onSave()
                }
                .disabled(item.displayAlias == nil && aliasText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Guardar", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360, alignment: .leading)
    }
}

private struct MonitorStatusView: View {
    let isRunning: Bool
    @State private var isShowingDetails = false

    var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            Image(systemName: isRunning ? "checkmark.circle.fill" : "pause.circle")
                .foregroundStyle(isRunning ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .help(isRunning ? "Monitor del portapapeles activo" : "Monitor del portapapeles pausado")
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    isRunning ? "Monitor activo" : "Monitor pausado",
                    systemImage: isRunning ? "checkmark.circle.fill" : "pause.circle"
                )
                .foregroundStyle(isRunning ? .green : .secondary)
                .font(.headline)

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(width: 280, alignment: .leading)
        }
    }

    private var statusMessage: String {
        if isRunning {
            return "Copy&Paste esta escuchando cambios del portapapeles para guardar nuevos registros."
        }

        return "Copy&Paste no esta capturando cambios del portapapeles en este momento."
    }
}

private struct AccessibilityStatusButton: View {
    @ObservedObject var controller: AccessibilityPermissionController
    @State private var isShowingDetails = false

    var body: some View {
        Button {
            controller.refresh()
            isShowingDetails.toggle()
        } label: {
            Image(systemName: controller.isTrusted ? "info.circle.fill" : "info.circle")
                .foregroundStyle(controller.isTrusted ? .green : .orange)
        }
        .buttonStyle(.borderless)
        .help(controller.isTrusted ? "Accesibilidad activa" : "Accesibilidad pendiente")
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    controller.isTrusted ? "Accesibilidad activa" : "Accesibilidad pendiente",
                    systemImage: controller.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(controller.isTrusted ? .green : .orange)
                .font(.headline)

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Actualizar") {
                        controller.refresh()
                    }

                    if !controller.isTrusted {
                        Button("Abrir Ajustes") {
                            controller.requestPermissionAndOpenSettings()
                        }
                    }
                }
            }
            .padding()
            .frame(width: 280, alignment: .leading)
        }
    }

    private var statusMessage: String {
        if controller.isTrusted {
            return "Copy&Paste tiene permiso para enviar el pegado automático."
        }

        return controller.guidanceMessage
            ?? "Activa Copy&Paste en Accesibilidad para permitir el pegado automático."
    }
}

#Preview {
    let container = try! ModelContainer(
        for: ClipboardItem.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let clipboardController = ClipboardController(modelContainer: container, startsMonitoring: false)
    let accessibilityPermissionController = AccessibilityPermissionController()

    ContentView()
        .environmentObject(clipboardController)
        .environmentObject(accessibilityPermissionController)
        .environmentObject(HistoryWindowController(
            clipboardController: clipboardController,
            accessibilityPermissionController: accessibilityPermissionController,
            modelContainer: container
        ))
}
