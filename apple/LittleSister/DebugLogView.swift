//
//  DebugLogView.swift
//  LittleSister
//

import SwiftUI
import AppKit

struct DebugLogView: View {
    private let log = DebugLog.shared

    var body: some View {
        VStack(spacing: 0) {
            List(log.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("[\(entry.category.rawValue)] \(entry.message)")
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.formattedForClipboard(), forType: .string)
                }
                .padding()
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        .onDisappear {
            NotificationCenter.default.post(name: .debugLogWindowClosed, object: nil)
        }
    }
}
