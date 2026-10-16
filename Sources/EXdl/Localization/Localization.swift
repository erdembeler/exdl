import Foundation
import SwiftUI

/// Languages the interface is available in.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case turkish = "tr"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    /// Turkish when the system prefers it, English otherwise.
    static var systemDefault: AppLanguage {
        for code in Locale.preferredLanguages {
            if code.hasPrefix("tr") { return .turkish }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }
}

/// Thread-safe holder for the active language, so `tr()` can be called from any context
/// (including `LocalizedError` descriptions and detached tasks).
enum Localizer {
    static let defaultsKey = "appLanguage"

    private static let lock = NSLock()
    private static var current: AppLanguage = {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
    }()

    static var language: AppLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            return current
        }
        set {
            lock.lock()
            current = newValue
            lock.unlock()
        }
    }

    /// True once the user has picked a language (or the first-run guide has stored one).
    static var hasStoredChoice: Bool {
        UserDefaults.standard.string(forKey: defaultsKey) != nil
    }
}

/// Observable wrapper SwiftUI views depend on, so they re-render when the language changes.
@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published private(set) var language: AppLanguage

    private init() {
        language = Localizer.language
    }

    func setLanguage(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        UserDefaults.standard.set(newValue.rawValue, forKey: Localizer.defaultsKey)
        Localizer.language = newValue
        language = newValue
    }

    /// Persists the language that is currently active (used when the user keeps the suggested one).
    func commitCurrentLanguage() {
        UserDefaults.standard.set(language.rawValue, forKey: Localizer.defaultsKey)
    }
}

/// Looks up `key` (the English text) in the active language. Named placeholders such as
/// `{app}` are replaced from `values`, so word order can differ between languages.
func tr(_ key: String, _ values: [String: String] = [:]) -> String {
    var text = key
    if Localizer.language == .turkish, let translated = TurkishStrings.table[key] {
        text = translated
    }
    for (name, value) in values {
        text = text.replacingOccurrences(of: "{\(name)}", with: value)
    }
    return text
}
