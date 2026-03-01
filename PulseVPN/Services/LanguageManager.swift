import SwiftUI

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case ar = "ar"
    case de = "de"
    case en = "en"
    case es = "es"
    case fr = "fr"
    case he = "he"
    case id = "id"
    case ja = "ja"
    case ptBR = "pt-BR"
    case ru = "ru"
    case tr = "tr"
    case uk = "uk"
    case vi = "vi"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "🌐 " + String(localized: "System Default")
        case .ar: "🇸🇦 العربية"
        case .de: "🇩🇪 Deutsch"
        case .en: "🇬🇧 English"
        case .es: "🇪🇸 Español"
        case .fr: "🇫🇷 Français"
        case .he: "🇮🇱 עברית"
        case .id: "🇮🇩 Bahasa Indonesia"
        case .ja: "🇯🇵 日本語"
        case .ptBR: "🇧🇷 Português (Brasil)"
        case .ru: "🇷🇺 Русский"
        case .tr: "🇹🇷 Türkçe"
        case .uk: "🇺🇦 Українська"
        case .vi: "🇻🇳 Tiếng Việt"
        case .zhHans: "🇨🇳 简体中文"
        case .zhHant: "🇹🇼 繁體中文"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: nil
        default: Locale(identifier: rawValue)
        }
    }
}

// MARK: - Language Manager

@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "doppler_app_language")
        }
    }

    private static let rtlLanguages: Set<String> = ["he", "ar"]

    private static let supportedCodes: Set<String> = Set(
        AppLanguage.allCases.compactMap { $0 == .system ? nil : $0.rawValue }
    )

    var effectiveLocale: Locale {
        if let locale = selectedLanguage.locale {
            return locale
        }
        // System mode: use system preferred language if supported
        let preferred = Locale.preferredLanguages.first ?? "en"
        let langCode = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
        if Self.supportedCodes.contains(langCode) {
            return Locale(identifier: langCode)
        }
        return Locale(identifier: "en")
    }

    var layoutDirection: LayoutDirection {
        let langCode = effectiveLocale.language.languageCode?.identifier ?? "en"
        return Self.rtlLanguages.contains(langCode) ? .rightToLeft : .leftToRight
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: "doppler_app_language") ?? "system"
        self.selectedLanguage = AppLanguage(rawValue: stored) ?? .system
    }
}
