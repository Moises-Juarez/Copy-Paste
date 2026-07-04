//
//  Item.swift
//  Copy&Paste
//
//  Created by E. Moisés Juárez Hernández on 03/07/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
