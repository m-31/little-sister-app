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
}
