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

    enum Category: String, CaseIterable, Identifiable {
        case lifecycle, poll, notification, settings, menu

        var id: String { rawValue }
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

    // Formats entries as plain text, newest first, for clipboard export.
    // Defaults to the whole buffer; the Debug Log window passes its currently
    // visible subset when a filter is active.
    func formattedForClipboard(_ subset: [DebugLogEntry]? = nil) -> String {
        (subset ?? entries).reversed().map { entry in
            let ts = entry.timestamp.formatted(date: .omitted, time: .standard)
            return "[\(ts)] \(entry.category.rawValue): \(entry.message)"
        }.joined(separator: "\n")
    }

    // Clears the buffer — the Debug Log window's Clear button, and tests
    // resetting shared state between runs.
    func reset() {
        entries.removeAll()
    }

    // The Debug Log window's filtering, kept here as a pure function so it can
    // be tested without a window. Hidden categories are dropped first; an empty
    // query then matches everything, and a non-empty one matches the message or
    // the category name, case-insensitively.
    static func visibleEntries(
        from entries: [DebugLogEntry],
        hiding hidden: Set<DebugLogEntry.Category>,
        matching query: String
    ) -> [DebugLogEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            guard !hidden.contains(entry.category) else { return false }
            guard !needle.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(needle)
                || entry.category.rawValue.localizedCaseInsensitiveContains(needle)
        }
    }
}
