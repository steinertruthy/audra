import Foundation
import Security

/// Keys shared between `@AppStorage` in views and the processing services.
enum PrefKey {
    static let language = "transcription.language"          // "auto" or a locale identifier
    static let autoSummarize = "summary.auto"
    static let summaryProvider = "summary.provider"         // SummaryProvider.rawValue
    static let summaryDetail = "summary.detail"             // SummaryDetail.rawValue
    static let claudeConsent = "summary.claude.consent"
    static let claudeModel = "summary.claude.model"
}

enum SummaryProvider: String, CaseIterable, Identifiable {
    case apple, claude
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: tr("Apple Intelligence (no dispositivo)")
        case .claude: tr("Claude (Anthropic API)")
        }
    }
}

enum Preferences {
    static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            PrefKey.language: "auto",
            PrefKey.autoSummarize: true,
            PrefKey.summaryProvider: SummaryProvider.apple.rawValue,
            PrefKey.summaryDetail: SummaryDetail.standard.rawValue,
            PrefKey.claudeConsent: false,
            PrefKey.claudeModel: ClaudeSummarizer.defaultModel,
        ])
    }

    static var language: String { defaults.string(forKey: PrefKey.language) ?? "auto" }
    static var autoSummarize: Bool { defaults.bool(forKey: PrefKey.autoSummarize) }
    static var summaryProvider: SummaryProvider {
        SummaryProvider(rawValue: defaults.string(forKey: PrefKey.summaryProvider) ?? "") ?? .apple
    }
    static var summaryDetail: SummaryDetail {
        SummaryDetail(rawValue: defaults.string(forKey: PrefKey.summaryDetail) ?? "") ?? .standard
    }
    static var claudeConsent: Bool { defaults.bool(forKey: PrefKey.claudeConsent) }
    static var claudeModel: String {
        let value = defaults.string(forKey: PrefKey.claudeModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? ClaudeSummarizer.defaultModel : value
    }
}

/// Minimal Keychain wrapper for the optional API key.
enum Keychain {
    private static let service = "app.audra.mac.anthropic"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String) -> Bool {
        delete()
        guard !value.isEmpty else { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }
}
