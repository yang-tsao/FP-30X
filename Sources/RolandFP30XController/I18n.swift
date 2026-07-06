import Foundation

private let kAppLanguage = "app_language"

private let uiBundle: Bundle = {
    let code = UserDefaults.standard.string(forKey: kAppLanguage)
        ?? Locale.current.language.languageCode?.identifier
        ?? "en"
    // Normalize: map system locale codes like "zh-Hans" → "zh"
    let lang = code.hasPrefix("zh") ? "zh" : (code.hasPrefix("es") ? "es" : "en")
    if let path = Bundle.module.path(forResource: lang, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle
    }
    return .module
}()

func loc(_ key: String) -> String {
    uiBundle.localizedString(forKey: key, value: key, table: nil)
}

func locf(_ key: String, _ args: CVarArg...) -> String {
    let fmt = loc(key)
    if args.isEmpty { return fmt }
    return String(format: fmt, locale: Locale.current, arguments: args)
}

func setAppLanguage(_ code: String) {
    UserDefaults.standard.set(code, forKey: kAppLanguage)
}
