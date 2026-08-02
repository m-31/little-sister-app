//
//  DebugLogView.swift
//  LittleSister
//

import AppKit
import SwiftUI

struct DebugLogView: View {
    private let log = DebugLog.shared

    @State private var query = ""
    @State private var hiddenCategories: Set<DebugLogEntry.Category> = []

    // Oldest-first, as stored; the list and the clipboard both reverse it.
    private var visible: [DebugLogEntry] {
        DebugLog.visibleEntries(from: log.entries, hiding: hiddenCategories, matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            entryList
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 380)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(DebugLogEntry.Category.allCases) { category in
                Toggle(category.rawValue, isOn: isShown(category))
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Show \(category.rawValue) entries")
            }
            Spacer(minLength: 12)
            searchField
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $query)
                .textFieldStyle(.plain)
                .frame(width: 150)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear the filter")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private func isShown(_ category: DebugLogEntry.Category) -> Binding<Bool> {
        Binding(
            get: { !hiddenCategories.contains(category) },
            set: { shown in
                if shown { hiddenCategories.remove(category) }
                else { hiddenCategories.insert(category) }
            }
        )
    }

    // MARK: - Entries

    private var entryList: some View {
        List(visible.reversed()) { entry in
            DebugLogRow(entry: entry)
                .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        }
        .listStyle(.plain)
        .textSelection(.enabled)
        .overlay {
            if visible.isEmpty {
                Text(log.entries.isEmpty
                     ? "No entries yet."
                     : "No entries match the current filter.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { log.reset() }
                .disabled(log.entries.isEmpty)
            // The label always states what the button will actually copy, so a
            // filtered view never silently puts hidden entries on the clipboard.
            Button(isFiltered ? "Copy Filtered" : "Copy All") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(log.formattedForClipboard(visible), forType: .string)
            }
            .disabled(visible.isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var isFiltered: Bool {
        !hiddenCategories.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var countLabel: String {
        isFiltered
            ? "\(visible.count) of \(log.entries.count) entries"
            : "\(log.entries.count) entries"
    }
}

// One entry per row: a fixed time column, a fixed-width category badge, then
// the message. Short entries occupy a single line; a long one (a committed
// settings dump, say) wraps within the message column only, so the time and
// category columns stay aligned down the whole list.
private struct DebugLogRow: View {
    let entry: DebugLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            // lineLimit + fixedSize keep the longest name ("notification") on one
            // line; the column is then sized to hold that badge whole, so every
            // message starts at the same x regardless of category.
            Text(entry.category.rawValue)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(entry.category.tint)
                .background(entry.category.tint.opacity(0.15), in: Capsule())
                .frame(width: 100, alignment: .leading)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Presentation only — kept out of DebugLog.swift, which stays free of SwiftUI.
private extension DebugLogEntry.Category {
    var tint: Color {
        switch self {
        case .lifecycle: return .purple
        case .poll: return .gray
        case .notification: return .orange
        case .settings: return .blue
        case .menu: return .teal
        }
    }
}
