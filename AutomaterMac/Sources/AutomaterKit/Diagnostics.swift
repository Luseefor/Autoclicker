import Foundation
import os

/// Small, local-only diagnostics buffer for support and release testing.
/// It deliberately excludes clicked coordinates, typed text, window titles,
/// and app names. Nothing in this buffer is transmitted by Automater.
public enum Diagnostics {
    private static let log = Logger(subsystem: "com.luseefor.automater", category: "diagnostics")
    private static let maxEntries = 200

    public static func record(_ category: String, _ detail: String) {
        log.error("\(category, privacy: .public): \(detail, privacy: .public)")
        let existing = try? Data(contentsOf: Storage.diagnosticsURL)
        var entries = existing.flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [[String: String]]
        } ?? []
        entries.append([
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "category": category,
            "detail": detail,
        ])
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted]) else { return }
        try? data.write(to: Storage.diagnosticsURL, options: .atomic)
    }
}
