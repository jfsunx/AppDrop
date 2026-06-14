import Foundation

enum L10n {
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    static func text(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}
