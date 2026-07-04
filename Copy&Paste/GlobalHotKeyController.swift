//
//  GlobalHotKeyController.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import Carbon
import Combine
import Foundation

final class GlobalHotKeyController: ObservableObject {
    @Published private(set) var isRegistered = false
    @Published private(set) var errorMessage: String?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: (() -> Void)?

    func registerCommandShiftV(action: @escaping () -> Void) {
        self.action = action

        guard eventHandlerRef == nil, hotKeyRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard hotKeyID.signature == GlobalHotKeyController.hotKeySignature else {
                    return noErr
                }

                let controller = Unmanaged<GlobalHotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                controller.handleHotKeyPressed()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            errorMessage = "No se pudo registrar el atajo global: \(handlerStatus)"
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            errorMessage = "No se pudo registrar Cmd+Shift+V: \(registrationStatus)"
            unregister()
            return
        }

        isRegistered = true
        errorMessage = nil
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        isRegistered = false
    }

    private func handleHotKeyPressed() {
        DispatchQueue.main.async { [action] in
            action?()
        }
    }

    private static let hotKeySignature: OSType = 0x43505354
}
