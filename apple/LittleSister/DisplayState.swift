//
//  DisplayState.swift
//  LittleSister
//

import Foundation

enum DisplayState: Equatable {
    case healthy
    case warning(isStale: Bool)
    case error
    case maintenance
    case undefined(reason: String)    // the server explicitly reported UNDEFINED
    case unavailable(reason: String)  // the client couldn't reach or parse the server at all
}

extension DisplayState {
    var symbol: String {
        switch self {
        case .healthy:     return "checkmark.circle.fill"
        case .warning:     return "exclamationmark.triangle.fill"
        case .error:       return "xmark.circle.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .undefined:   return "questionmark.circle"
        case .unavailable: return "questionmark.circle"
        }
    }

    var label: String {
        switch self {
        case .healthy:              return "ok"
        case .warning(let isStale): return isStale ? "warn (stale)" : "warn"
        case .error:                return "error"
        case .maintenance:          return "maintenance"
        case .undefined:            return "undefined"
        case .unavailable:          return "unavailable"
        }
    }

    // Ignores associated values — used by notification(from:to:) to detect case changes.
    // .undefined and .unavailable count as the same case as each other: switching between
    // "server says undefined" and "can't reach the server" isn't a meaningful transition.
    func isSameCase(as other: DisplayState) -> Bool {
        switch (self, other) {
        case (.healthy, .healthy), (.warning, .warning), (.error, .error),
             (.maintenance, .maintenance),
             (.undefined, .undefined), (.unavailable, .unavailable),
             (.undefined, .unavailable), (.unavailable, .undefined):
            return true
        default:
            return false
        }
    }
}

func displayState(for node: StatusNode) -> DisplayState {
    switch node.code {
    case .ok:
        return node.stale ? .warning(isStale: true) : .healthy
    case .warn:
        return .warning(isStale: false)
    case .error:
        return .error
    case .maintenance:
        return .maintenance
    case .undefined:
        return .undefined(reason: node.reasons.first ?? "Status undefined")
    }
}

// Returns a notification (title, body) when the transition from `from` to `to` is
// meaningful, or nil when no notification should fire (same case, or no prior state).
// Comparison is by case only — associated values (isStale, reason) are ignored.
// .undefined and .unavailable are treated as the same case for anti-spam purposes.
func notification(from: DisplayState?, to: DisplayState) -> (title: String, body: String)? {
    guard let from else { return nil }
    guard !from.isSameCase(as: to) else { return nil }

    switch (from, to) {
    case (.healthy, .warning):
        return ("Monitoring warning", "")
    case (.healthy, .error):
        return ("Monitoring error", "")
    case (.warning, .error):
        return ("Monitoring error", "")
    case (.error, .healthy):
        return ("Service recovered", "")
    case (.error, .maintenance):
        return ("Monitoring placed in maintenance", "")
    case (.maintenance, .error):
        return ("Maintenance ended; service is unhealthy", "")
    case (_, .undefined), (_, .unavailable):
        return ("Monitoring status unavailable", "")
    case (.undefined, .healthy), (.unavailable, .healthy):
        return ("Monitoring status available again", "")
    case (.undefined, .error), (.unavailable, .error):
        return ("Monitoring error", "")
    default:
        return ("Monitoring: \(to.label)", "")
    }
}
