//
//  DebugLogTests.swift
//  LittleSisterTests
//

import Testing
@testable import LittleSister

@Suite("DebugLog ring buffer")
@MainActor
struct DebugLogTests {

    @Test("Ring buffer drops oldest entry once past 200")
    func ringBufferCapacity() {
        DebugLog.shared.reset()
        for i in 1...201 {
            DebugLog.shared.record("entry \(i)", category: .poll)
        }
        #expect(DebugLog.shared.entries.count == 200)
        #expect(DebugLog.shared.entries.first?.message == "entry 2")
    }

    @Test("formattedForClipboard produces one line per entry")
    func formattedForClipboard() {
        DebugLog.shared.reset()
        DebugLog.shared.record("alpha", category: .lifecycle)
        DebugLog.shared.record("beta", category: .poll)
        let text = DebugLog.shared.formattedForClipboard()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2)
    }

    @Test("formattedForClipboard formats only the subset it is given")
    func formattedForClipboardSubset() {
        DebugLog.shared.reset()
        DebugLog.shared.record("alpha", category: .lifecycle)
        DebugLog.shared.record("beta", category: .poll)
        let polls = DebugLog.shared.entries.filter { $0.category == .poll }
        let text = DebugLog.shared.formattedForClipboard(polls)
        #expect(text.contains("beta"))
        #expect(!text.contains("alpha"))
    }

    @Test("Hidden categories are dropped, everything else survives an empty query")
    func filterHidesCategories() {
        DebugLog.shared.reset()
        DebugLog.shared.record("alpha", category: .lifecycle)
        DebugLog.shared.record("beta", category: .poll)
        DebugLog.shared.record("gamma", category: .menu)
        let visible = DebugLog.visibleEntries(
            from: DebugLog.shared.entries, hiding: [.poll], matching: "")
        #expect(visible.map(\.message) == ["alpha", "gamma"])
    }

    @Test("A query matches message or category name, case-insensitively")
    func filterMatchesQuery() {
        DebugLog.shared.reset()
        DebugLog.shared.record("Window shown: Settings", category: .menu)
        DebugLog.shared.record("Poll: warn", category: .poll)
        let entries = DebugLog.shared.entries

        let byMessage = DebugLog.visibleEntries(from: entries, hiding: [], matching: "WARN")
        #expect(byMessage.map(\.message) == ["Poll: warn"])

        let byCategory = DebugLog.visibleEntries(from: entries, hiding: [], matching: "menu")
        #expect(byCategory.map(\.message) == ["Window shown: Settings"])

        let whitespaceOnly = DebugLog.visibleEntries(from: entries, hiding: [], matching: "   ")
        #expect(whitespaceOnly.count == 2)
    }

    @Test("Hidden categories win over a query that would otherwise match")
    func filterCombinesCategoryAndQuery() {
        DebugLog.shared.reset()
        DebugLog.shared.record("Poll: warn", category: .poll)
        DebugLog.shared.record("Menu opened: warn", category: .menu)
        let visible = DebugLog.visibleEntries(
            from: DebugLog.shared.entries, hiding: [.poll], matching: "warn")
        #expect(visible.map(\.message) == ["Menu opened: warn"])
    }
}
