import Foundation
import Observation

/// Interface languages. "system" follows the macOS language order.
enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, pt, en, es
    var id: String { rawValue }

    /// Name shown in its own language, so anyone can find theirs.
    var nativeName: String {
        switch self {
        case .system: tr("Igual ao sistema")
        case .pt: "Português (Brasil)"
        case .en: "English"
        case .es: "Español"
        }
    }
}

/// Live interface localization. Reading `code` inside a view body registers an observation
/// dependency, so changing the language re-renders the whole UI instantly.
@Observable
final class Localization: @unchecked Sendable {
    static let shared = Localization()
    static let preferenceKey = "interface.language"
    static let supported = ["pt", "en", "es"]

    /// Effective language code ("pt", "en" or "es").
    private(set) var code: String
    var preference: InterfaceLanguage {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.preferenceKey)
            code = Self.resolve(preference)
            // System-provided strings (standard menus, panels) follow on next launch.
            if preference == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([Self.appleLanguage(code)], forKey: "AppleLanguages")
            }
        }
    }

    private init() {
        let stored = InterfaceLanguage(rawValue: UserDefaults.standard.string(forKey: Self.preferenceKey) ?? "") ?? .system
        preference = stored
        code = Self.resolve(stored)
    }

    /// Forces a language without persisting it (tests, previews).
    func use(_ code: String) { self.code = code }

    var locale: Locale { Locale(identifier: Self.appleLanguage(code)) }

    static func resolve(_ preference: InterfaceLanguage) -> String {
        if preference != .system { return preference.rawValue }
        // AppleLanguages may hold our own override; read the user's global order instead.
        let global = (UserDefaults(suiteName: UserDefaults.globalDomain)?.array(forKey: "AppleLanguages") as? [String])
            ?? Locale.preferredLanguages
        for language in global {
            let prefix = String(language.prefix(2)).lowercased()
            if supported.contains(prefix) { return prefix }
        }
        return "en"
    }

    static func appleLanguage(_ code: String) -> String {
        switch code {
        case "pt": "pt-BR"
        case "es": "es"
        default: "en"
        }
    }
}

/// Translates a Portuguese source string into the interface language.
/// `%@` placeholders are filled in order with `args`.
func tr(_ key: String, _ args: Any...) -> String {
    let code = Localization.shared.code
    var text = code == "pt" ? key : (Translations.table[code]?[key] ?? key)
    for arg in args {
        guard let range = text.range(of: "%@") else { break }
        text.replaceSubrange(range, with: "\(arg)")
    }
    return text
}
