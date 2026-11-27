import Foundation

/// 2.100 : journal de connexion (gardé sur l'iPhone, visible dans Réglages › Journal de connexion)
/// pour comprendre les fois où le boîtier ou le trajet ne démarre pas.
enum LMLog {
    private static let key = "lmlog"
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "dd/MM HH:mm:ss"; return f }()
    private static var last = ""
    static func add(_ s: String) {
        if s == last { return }
        last = s
        var a = UserDefaults.standard.stringArray(forKey: key) ?? []
        a.append(fmt.string(from: Date()) + "  " + s)
        if a.count > 400 { a.removeFirst(a.count - 400) }
        UserDefaults.standard.set(a, forKey: key)
    }
    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
