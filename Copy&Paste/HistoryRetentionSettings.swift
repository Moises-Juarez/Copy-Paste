//
//  HistoryRetentionSettings.swift
//  Copy&Paste
//
//  Created by E. Moises Juarez Hernandez on 23/07/2026.
//

import Combine
import Foundation

@MainActor
final class HistoryRetentionSettings: ObservableObject {
    static let maxUnpinnedItemOptions = [100, 300, 500, 1000, 2000]
    static let retentionDayOptions = [0, 7, 30, 90, 180, 365]
    static let maxStorageMegabyteOptions = [100, 250, 500, 1024, 2048]

    @Published private(set) var maxUnpinnedItems: Int
    @Published private(set) var retentionDays: Int
    @Published private(set) var maxStorageMegabytes: Int

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedMaxItems = userDefaults.integer(forKey: Self.maxUnpinnedItemsKey)
        self.maxUnpinnedItems = Self.normalizedMaxUnpinnedItems(storedMaxItems)

        let storedRetentionDays = userDefaults.integer(forKey: Self.retentionDaysKey)
        self.retentionDays = Self.normalizedRetentionDays(storedRetentionDays)

        let storedStorageMegabytes = userDefaults.object(forKey: Self.maxStorageMegabytesKey) as? Int
        self.maxStorageMegabytes = Self.normalizedMaxStorageMegabytes(
            storedStorageMegabytes ?? Self.defaultMaxStorageMegabytes
        )
    }

    var retentionCutoffDate: Date? {
        guard retentionDays > 0 else {
            return nil
        }

        return Date().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
    }

    var summary: String {
        "\(maxUnpinnedItems) registros, \(Self.retentionTitle(for: retentionDays).lowercased()), \(Self.storageTitle(for: maxStorageMegabytes))"
    }

    var maxStorageBytes: Int64 {
        Int64(maxStorageMegabytes) * 1_024 * 1_024
    }

    func setMaxUnpinnedItems(_ value: Int) {
        let normalizedValue = Self.normalizedMaxUnpinnedItems(value)
        guard maxUnpinnedItems != normalizedValue else {
            return
        }

        maxUnpinnedItems = normalizedValue
        userDefaults.set(normalizedValue, forKey: Self.maxUnpinnedItemsKey)
    }

    func setRetentionDays(_ value: Int) {
        let normalizedValue = Self.normalizedRetentionDays(value)
        guard retentionDays != normalizedValue else {
            return
        }

        retentionDays = normalizedValue
        userDefaults.set(normalizedValue, forKey: Self.retentionDaysKey)
    }

    func setMaxStorageMegabytes(_ value: Int) {
        let normalizedValue = Self.normalizedMaxStorageMegabytes(value)
        guard maxStorageMegabytes != normalizedValue else {
            return
        }

        maxStorageMegabytes = normalizedValue
        userDefaults.set(normalizedValue, forKey: Self.maxStorageMegabytesKey)
    }

    static func retentionTitle(for days: Int) -> String {
        switch days {
        case 0:
            return "Siempre"
        case 7:
            return "7 dias"
        case 30:
            return "30 dias"
        case 90:
            return "90 dias"
        case 180:
            return "180 dias"
        case 365:
            return "365 días"
        default:
            return "\(days) dias"
        }
    }

    static func storageTitle(for megabytes: Int) -> String {
        switch megabytes {
        case 1024:
            return "1 GB"
        case 2048:
            return "2 GB"
        default:
            return "\(megabytes) MB"
        }
    }

    private static func normalizedMaxUnpinnedItems(_ value: Int) -> Int {
        guard maxUnpinnedItemOptions.contains(value) else {
            return defaultMaxUnpinnedItems
        }

        return value
    }

    private static func normalizedRetentionDays(_ value: Int) -> Int {
        guard retentionDayOptions.contains(value) else {
            return defaultRetentionDays
        }

        return value
    }

    private static func normalizedMaxStorageMegabytes(_ value: Int) -> Int {
        guard value > 0 else {
            return defaultMaxStorageMegabytes
        }

        return value
    }

    private static let defaultMaxUnpinnedItems = 500
    private static let defaultRetentionDays = 0
    private static let defaultMaxStorageMegabytes = 500
    private static let maxUnpinnedItemsKey = "historyRetention.maxUnpinnedItems"
    private static let retentionDaysKey = "historyRetention.retentionDays"
    private static let maxStorageMegabytesKey = "historyRetention.maxStorageMegabytes"
}
