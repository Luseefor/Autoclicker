import Foundation

/// JSON persistence compatible with the Python app's on-disk layout:
/// ~/Library/Application Support/Automater/{settings.json,macros/*.json}
public enum Storage {
    public static let appDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AutomaterMac", isDirectory: true)
    public static let macrosDir = appDir.appendingPathComponent("macros", isDirectory: true)
    public static let settingsURL = appDir.appendingPathComponent("settings.json")

    public static func ensureDirs() {
        try? FileManager.default.createDirectory(at: macrosDir, withIntermediateDirectories: true)
    }

    // MARK: - Settings

    public static func loadSettings() -> [String: Any] {
        ensureDirs()
        guard let data = try? Data(contentsOf: settingsURL),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let dict = raw as? [String: Any] else { return defaults }
        return defaults.merging(dict) { _, new in new }
    }

    public static func saveSettings(_ dict: [String: Any]) {
        ensureDirs()
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: settingsURL)
        }
    }

    public static let defaults: [String: Any] = [
        "click_interval_h": 0,
        "click_interval_m": 0,
        "click_interval_s": 0,
        "click_interval_ms": 100,
        "jitter_ms": 0,
        "repeat_count": 0,
        "mouse_button": "left",
        "click_kind": "single",
        "mode": "multipoint",
        "background_to_app": false,
        "delivery_mode": "accessibility",
        "hotkey_toggle": "ctrl+alt+a",
        "hotkey_record": "ctrl+alt+r",
        "hotkey_stop": "ctrl+alt+s",
    ]

    // MARK: - Macros

    public static func listMacros() -> [Macro] {
        ensureDirs()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: macrosDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Macro.self, from: data)
        }.sorted { $0.name < $1.name }
    }

    @discardableResult
    public static func saveMacro(_ macro: Macro) -> Bool {
        ensureDirs()
        let url = macrosDir.appendingPathComponent("\(macro.id).json")
        guard let data = try? JSONEncoder().encode(macro) else { return false }
        do { try data.write(to: url); return true } catch { return false }
    }

    public static func deleteMacro(id: String) {
        try? FileManager.default.removeItem(
            at: macrosDir.appendingPathComponent("\(id).json")
        )
    }
}
