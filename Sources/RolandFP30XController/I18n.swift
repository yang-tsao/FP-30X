import Foundation

func loc(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

func locf(_ key: String, _ args: CVarArg...) -> String {
    let fmt = loc(key)
    if args.isEmpty { return fmt }
    return String(format: fmt, locale: Locale.current, arguments: args)
}
