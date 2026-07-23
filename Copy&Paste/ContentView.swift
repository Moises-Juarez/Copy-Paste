//
//  ContentView.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import AppKit
import SwiftUI
import SwiftData

private struct HistoryDisplaySnapshot {
    let filteredItems: [ClipboardItem]
    let pinnedItems: [ClipboardItem]
    let historyItems: [ClipboardItem]
    let allHistoryItems: [ClipboardItem]

    func visibleItems(isPinnedSectionExpanded: Bool) -> [ClipboardItem] {
        let visiblePinnedItems = isPinnedSectionExpanded ? pinnedItems : []
        return visiblePinnedItems + historyItems
    }
}

struct ContentView: View {
    @EnvironmentObject private var clipboardController: ClipboardController
    @EnvironmentObject private var accessibilityPermissionController: AccessibilityPermissionController
    @EnvironmentObject private var historyWindowController: HistoryWindowController
    @EnvironmentObject private var retentionSettings: HistoryRetentionSettings

    @State private var searchText = ""
    @State private var aliasEditorItem: ClipboardItem?
    @State private var aliasText = ""
    @State private var isShowingAliasEditor = false
    @State private var isShowingClearHistoryConfirmation = false
    @State private var isShowingUnavailableFilesConfirmation = false
    @State private var isPinnedSectionExpanded = false
    @State private var pinnedSectionExpandedBeforeSearch = false
    @State private var selectedItemID: UUID?
    @State private var historyScrollPosition = ScrollPosition(edge: .top)
    @State private var isResettingScrollForPresentation = false

    @FocusState private var isSearchFieldFocused: Bool

    private var items: [ClipboardItem] {
        clipboardController.items
    }

    private var displaySnapshot: HistoryDisplaySnapshot {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredItems: [ClipboardItem]

        if query.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.matchesSearch(query)
            }
        }

        return HistoryDisplaySnapshot(
            filteredItems: filteredItems,
            pinnedItems: clipboardController.orderedPinnedItems(from: filteredItems),
            historyItems: filteredItems.filter { !$0.isPinned },
            allHistoryItems: items.filter { !$0.isPinned }
        )
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleItems: [ClipboardItem] {
        displaySnapshot.visibleItems(isPinnedSectionExpanded: isPinnedSectionExpanded)
    }

    var body: some View {
        let snapshot = displaySnapshot

        NavigationStack {
            VStack(spacing: 0) {
                HistoryControlsBar(
                    isMonitoring: clipboardController.isMonitoring,
                    accessibilityPermissionController: accessibilityPermissionController,
                    retentionSettings: retentionSettings,
                    storageBytes: clipboardController.estimatedStorageBytes,
                    unavailableFileItemCount: clipboardController.unavailableFileItemCount,
                    canClearHistory: !snapshot.allHistoryItems.isEmpty,
                    onCapture: captureCurrentPasteboard,
                    onClearHistory: requestClearHistoryConfirmation,
                    onCleanUnavailableFiles: requestUnavailableFilesCleanup,
                    onRetentionSettingsChanged: applyRetentionSettings
                )

                Divider()

                ScrollViewReader { scrollProxy in
                    List(selection: $selectedItemID) {
                        if !snapshot.pinnedItems.isEmpty {
                            Section {
                                if isPinnedSectionExpanded {
                                    ForEach(snapshot.pinnedItems) { item in
                                        clipboardRow(for: item)
                                            .id(item.id)
                                            .tag(item.id)
                                            .moveDisabled(isSearching)
                                    }
                                    .onDelete { offsets in
                                        deleteItems(at: offsets, from: snapshot.pinnedItems)
                                    }
                                    .onMove(perform: movePinnedItems)
                                }
                            } header: {
                                Button(action: togglePinnedSection) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "chevron.right")
                                            .rotationEffect(.degrees(isPinnedSectionExpanded ? 90 : 0))

                                        Text("Fijos")

                                        Text("\(snapshot.pinnedItems.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(isPinnedSectionExpanded ? "Ocultar registros fijados" : "Mostrar registros fijados")
                            }
                        }

                        if !snapshot.historyItems.isEmpty {
                            Section("Historial") {
                                ForEach(snapshot.historyItems) { item in
                                    clipboardRow(for: item)
                                        .id(item.id)
                                        .tag(item.id)
                                }
                                .onDelete { offsets in
                                    deleteItems(at: offsets, from: snapshot.historyItems)
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
                        } else if snapshot.filteredItems.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }
                    .scrollPosition($historyScrollPosition)
                    .onChange(of: selectedItemID) { _, selectedItemID in
                        guard !isResettingScrollForPresentation,
                              let selectedItemID else {
                            return
                        }

                        scrollProxy.scrollTo(selectedItemID)
                    }
                    .onAppear {
                        resetScrollToTop()
                    }
                    .onChange(of: historyWindowController.presentationID) { _, _ in
                        resetScrollToTop()
                    }
                }
            }
            .navigationTitle("Copiados")
            .searchable(text: $searchText, prompt: "Buscar")
            .searchFocused($isSearchFieldFocused)
        }
        .onAppear(perform: prepareForPresentation)
        .onChange(of: historyWindowController.presentationID) { _, _ in
            prepareForPresentation()
        }
        .onChange(of: searchText, handleSearchChange)
        .onReceive(clipboardController.$items) { _ in
            ensureValidSelection()
        }
        .onReceive(historyWindowController.keyboardCommands) { command in
            handleKeyboardCommand(command)
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
        .confirmationDialog(
            "Limpiar archivos no disponibles",
            isPresented: $isShowingUnavailableFilesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Limpiar referencias", role: .destructive, action: cleanUnavailableFileReferences)
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se quitaran las rutas que ya no existen. Si un registro no conserva ningun archivo, se eliminara tambien, aunque este fijado.")
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
            fileMetadata: clipboardController.fileMetadata(for: item),
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

    private func movePinnedItems(from source: IndexSet, to destination: Int) {
        guard !isSearching else {
            return
        }

        var reorderedItems = displaySnapshot.pinnedItems
        reorderedItems.move(fromOffsets: source, toOffset: destination)
        clipboardController.setPinnedOrder(reorderedItems)
    }

    private func togglePinnedSection() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isPinnedSectionExpanded.toggle()
        }
        ensureValidSelection()
    }

    private func prepareForPresentation() {
        searchText = ""
        isPinnedSectionExpanded = false
        pinnedSectionExpandedBeforeSearch = false
        selectedItemID = displaySnapshot.historyItems.first?.id

        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    private func resetScrollToTop() {
        isResettingScrollForPresentation = true
        historyScrollPosition.scrollTo(edge: .top)

        DispatchQueue.main.async {
            historyScrollPosition.scrollTo(edge: .top)

            DispatchQueue.main.async {
                isResettingScrollForPresentation = false
            }
        }
    }

    private func handleSearchChange(_ previousValue: String, _ newValue: String) {
        let wasSearching = !previousValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isNowSearching = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !wasSearching && isNowSearching {
            pinnedSectionExpandedBeforeSearch = isPinnedSectionExpanded
            isPinnedSectionExpanded = true
        } else if wasSearching && !isNowSearching {
            isPinnedSectionExpanded = pinnedSectionExpandedBeforeSearch
        }

        selectedItemID = visibleItems.first?.id
    }

    private func ensureValidSelection() {
        guard let selectedItemID,
              visibleItems.contains(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = visibleItems.first?.id
            return
        }
    }

    private func handleKeyboardCommand(_ command: HistoryKeyboardCommand) {
        switch command {
        case .previous:
            moveSelection(by: -1)
        case .next:
            moveSelection(by: 1)
        case .pasteSelected:
            let currentVisibleItems = visibleItems
            let selectedItem = selectedItemID.flatMap { selectedID in
                currentVisibleItems.first(where: { $0.id == selectedID })
            }

            guard let item = selectedItem ?? currentVisibleItems.first else {
                return
            }

            selectedItemID = item.id
            pasteAndClose(item)
        }
    }

    private func moveSelection(by offset: Int) {
        let snapshot = displaySnapshot

        if !isSearching,
           offset < 0,
           !isPinnedSectionExpanded,
           let firstHistoryItemID = snapshot.historyItems.first?.id,
           selectedItemID == firstHistoryItemID,
           let firstPinnedItemID = snapshot.pinnedItems.first?.id {
            isPinnedSectionExpanded = true
            selectedItemID = firstPinnedItemID
            return
        }

        if !isSearching,
           offset > 0,
           isPinnedSectionExpanded,
           let lastPinnedItemID = snapshot.pinnedItems.last?.id,
           selectedItemID == lastPinnedItemID,
           let firstHistoryItemID = snapshot.historyItems.first?.id {
            isPinnedSectionExpanded = false
            selectedItemID = firstHistoryItemID
            return
        }

        let currentVisibleItems = snapshot.visibleItems(
            isPinnedSectionExpanded: isPinnedSectionExpanded
        )

        guard !currentVisibleItems.isEmpty else {
            selectedItemID = nil
            return
        }

        guard let selectedItemID,
              let currentIndex = currentVisibleItems.firstIndex(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = offset < 0 ? currentVisibleItems.last?.id : currentVisibleItems.first?.id
            return
        }

        let nextIndex = min(max(currentIndex + offset, 0), currentVisibleItems.count - 1)
        self.selectedItemID = currentVisibleItems[nextIndex].id
    }

    private func requestClearHistoryConfirmation() {
        isShowingClearHistoryConfirmation = true
    }

    private func clearHistory() {
        withAnimation {
            clipboardController.clearHistory()
        }
    }

    private func requestUnavailableFilesCleanup() {
        isShowingUnavailableFilesConfirmation = true
    }

    private func cleanUnavailableFileReferences() {
        withAnimation {
            clipboardController.cleanUnavailableFileReferences()
        }
    }

    private func applyRetentionSettings() {
        withAnimation {
            clipboardController.enforceRetentionPolicy()
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
    @ObservedObject var retentionSettings: HistoryRetentionSettings
    let storageBytes: Int64
    let unavailableFileItemCount: Int
    let canClearHistory: Bool
    let onCapture: () -> Void
    let onClearHistory: () -> Void
    let onCleanUnavailableFiles: () -> Void
    let onRetentionSettingsChanged: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MonitorStatusView(isRunning: isMonitoring)
                .padding(.leading, 4)

            AccessibilityStatusButton(controller: accessibilityPermissionController)

            HistoryRetentionSettingsButton(
                settings: retentionSettings,
                storageBytes: storageBytes,
                unavailableFileItemCount: unavailableFileItemCount,
                onCleanUnavailableFiles: onCleanUnavailableFiles,
                onChange: onRetentionSettingsChanged
            )

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

private struct HistoryRetentionSettingsButton: View {
    @ObservedObject var settings: HistoryRetentionSettings
    let storageBytes: Int64
    let unavailableFileItemCount: Int
    let onCleanUnavailableFiles: () -> Void
    let onChange: () -> Void

    @State private var isShowingSettings = false

    var body: some View {
        Button {
            isShowingSettings.toggle()
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("Configuracion del historial")
        .popover(isPresented: $isShowingSettings, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Historial", systemImage: "gearshape")
                    .font(.headline)

                Picker("Maximo", selection: maxItemsBinding) {
                    ForEach(HistoryRetentionSettings.maxUnpinnedItemOptions, id: \.self) { value in
                        Text("\(value) registros").tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Conservar", selection: retentionDaysBinding) {
                    ForEach(HistoryRetentionSettings.retentionDayOptions, id: \.self) { value in
                        Text(HistoryRetentionSettings.retentionTitle(for: value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                Picker("Espacio maximo", selection: maxStorageBinding) {
                    ForEach(HistoryRetentionSettings.maxStorageMegabyteOptions, id: \.self) { value in
                        Text(HistoryRetentionSettings.storageTitle(for: value)).tag(value)
                    }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: storageProgress)
                        .progressViewStyle(.linear)

                    Text("\(formattedStorageBytes) utilizados de \(HistoryRetentionSettings.storageTitle(for: settings.maxStorageMegabytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if unavailableFileItemCount > 0 {
                    Button(role: .destructive, action: onCleanUnavailableFiles) {
                        Label(
                            "\(unavailableFileItemCount) referencias no disponibles",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }

                Text("Los fijos se conservan siempre. No se eliminan aunque excedan estos limites.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Actual: \(settings.summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 320, alignment: .leading)
        }
    }

    private var maxItemsBinding: Binding<Int> {
        Binding(
            get: { settings.maxUnpinnedItems },
            set: { value in
                settings.setMaxUnpinnedItems(value)
                onChange()
            }
        )
    }

    private var retentionDaysBinding: Binding<Int> {
        Binding(
            get: { settings.retentionDays },
            set: { value in
                settings.setRetentionDays(value)
                onChange()
            }
        )
    }

    private var maxStorageBinding: Binding<Int> {
        Binding(
            get: { settings.maxStorageMegabytes },
            set: { value in
                settings.setMaxStorageMegabytes(value)
                onChange()
            }
        )
    }

    private var storageProgress: Double {
        guard settings.maxStorageBytes > 0 else {
            return 0
        }

        return min(Double(storageBytes) / Double(settings.maxStorageBytes), 1)
    }

    private var formattedStorageBytes: String {
        ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file)
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let fileMetadata: ClipboardFileMetadata?
    let onPaste: () -> Void
    let onPasteMode: (ClipboardPasteMode) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void
    let onEditAlias: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if item.isPinned {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .help("Arrastrar para ordenar")
            }

            Button(action: onPaste) {
                HStack(alignment: .top, spacing: 10) {
                    itemPreview

                    if item.isPinned {
                        pinnedContent
                    } else {
                        historyContent
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

    private var pinnedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let displayAlias = item.displayAlias {
                Text(displayAlias)
                    .font(.headline)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(item.preview.isEmpty ? "Texto sin vista previa" : item.preview)
                    .font(item.displayAlias == nil ? .body : .subheadline)
                    .foregroundStyle(item.displayAlias == nil ? .primary : .secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                ClipboardItemMetadataView(item: item, fileMetadata: fileMetadata)
            }
        }
    }

    private var historyContent: some View {
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

            HStack(spacing: 8) {
                ClipboardItemMetadataView(item: item, fileMetadata: fileMetadata)

                Spacer(minLength: 8)

                Text(item.copiedAt, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
        } else {
            Image(systemName: item.isFile ? "doc" : item.isPinned ? "pin.fill" : "doc.text")
                .foregroundStyle(item.isPinned ? .blue : .secondary)
                .frame(width: 48, height: 34)
        }
    }
}

private struct ClipboardItemMetadataView: View {
    let item: ClipboardItem
    let fileMetadata: ClipboardFileMetadata?

    var body: some View {
        HStack(spacing: 6) {
            Label(item.contentTypeTitle, systemImage: item.contentTypeSystemImage)

            Text(sizeDescription)

            if let fileMetadata, fileMetadata.unavailableFileCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(unavailableFilesHelp(count: fileMetadata.unavailableFileCount))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var sizeDescription: String {
        if item.isFile {
            guard let fileMetadata else {
                return "Calculando..."
            }

            if fileMetadata.representedBytes == 0, fileMetadata.unavailableFileCount > 0 {
                return "No disponible"
            }

            return ByteCountFormatter.string(
                fromByteCount: fileMetadata.representedBytes,
                countStyle: .file
            )
        }

        return ByteCountFormatter.string(
            fromByteCount: item.knownStorageBytes,
            countStyle: .file
        )
    }

    private func unavailableFilesHelp(count: Int) -> String {
        return count == 1
            ? "Un archivo ya no esta disponible"
            : "\(count) archivos ya no estan disponibles"
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
    let retentionSettings = HistoryRetentionSettings()
    let clipboardController = ClipboardController(
        modelContainer: container,
        startsMonitoring: false,
        retentionSettings: retentionSettings
    )
    let accessibilityPermissionController = AccessibilityPermissionController()

    ContentView()
        .environmentObject(clipboardController)
        .environmentObject(retentionSettings)
        .environmentObject(accessibilityPermissionController)
        .environmentObject(HistoryWindowController(
            clipboardController: clipboardController,
            accessibilityPermissionController: accessibilityPermissionController,
            modelContainer: container
        ))
}
