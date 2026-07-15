//
//  DebugLog.swift
//  LittleSister
//

import Foundation
import Observation
import os

struct DebugLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: Category
    let message: String

    enum Category: String {
        case lifecycle, poll, notification, settings
    }
}

@Observable
@MainActor
final class DebugLog {
    static let shared = DebugLog()

    private(set) var entries: [DebugLogEntry] = []
    private let capacity = 200
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "LittleSister",
        category: "DebugLog"
    )

    // Internal so tests can reset the shared instance between runs.
    internal init() {}

    func record(_ message: String, category: DebugLogEntry.Category) {
        let entry = DebugLogEntry(timestamp: Date(), category: category, message: message)
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        logger.log("\(category.rawValue, privacy: .public): \(message, privacy: .public)")
    }

    // Formats all current entries as plain text, newest first, for clipboard export.
    func formattedForClipboard() -> String {
        entries.reversed().map { entry in
            let ts = entry.timestamp.formatted(date: .omitted, time: .standard)
            return "[\(ts)] \(entry.category.rawValue): \(entry.message)"
        }.joined(separator: "\n")
    }

    // Clears the buffer — used only by tests to reset shared state between runs.
    func reset() {
        entries.removeAll()
    }
}
