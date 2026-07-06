import Foundation

public enum Lang: String, CaseIterable, Sendable {
    case en, es, zh

    var locale: Locale {
        switch self {
        case .es: return Locale(identifier: "es")
        case .zh: return Locale(identifier: "zh_Hans")
        default:  return Locale(identifier: "en")
        }
    }

    var bundle: Bundle {
        guard let path = Bundle.module.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
    }
}

public func tr(_ lang: Lang, _ key: String, _ args: CVarArg...) -> String {
    _tr(lang, key, args)
}

func _tr(_ lang: Lang, _ key: String, _ args: [CVarArg]) -> String {
    let fmt = lang.bundle.localizedString(forKey: key, value: key, table: nil)
    if args.isEmpty { return fmt }
    return String(format: fmt, locale: lang.locale, arguments: args)
}
