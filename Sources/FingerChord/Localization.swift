// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L10n.text("language.system")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
}

enum L10n {
    static var language =
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "system") ?? .system

    static var code: String {
        language == .system
            ? Bundle.preferredLocalizations(
                from: ["en", "zh-Hans", "zh-Hant"], forPreferences: Locale.preferredLanguages
            ).first ?? "en"
            : language.rawValue
    }

    // SwiftPM's default accessor does not search Contents/Resources in a packaged app.
    static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("FingerChord_FingerChord.bundle"),
            let bundle = Bundle(url: url)
        {
            return bundle
        }
        return Bundle.module
    }()

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let path = resources.path(forResource: code, ofType: "lproj")
        let bundle = path.flatMap(Bundle.init(path:)) ?? resources
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty
            ? format : String(format: format, locale: Locale(identifier: code), arguments: arguments)
    }
}
