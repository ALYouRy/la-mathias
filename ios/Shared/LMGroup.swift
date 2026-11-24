import Foundation

/// 2.91 : zone partagée entre l'appli et ses widgets (groupe d'applis).
/// SideStore renomme le groupe à l'installation (il ajoute l'identifiant de ton compte) et note le vrai nom
/// dans « ALTAppGroups » de l'Info.plist de l'appli : on le lit là, depuis l'appli comme depuis le widget.
enum LMGroup {
    static let base = "group.fr.lamathias.app"
    static let id: String = {
        func groups(_ url: URL) -> [String] {
            guard let d = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")) else { return [] }
            return (d["ALTAppGroups"] as? [String]) ?? []
        }
        var c = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]) ?? []
        if c.isEmpty, Bundle.main.bundleURL.pathExtension == "appex" {
            c = groups(Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent())
        }
        return c.first(where: { $0.hasPrefix(base) }) ?? c.first ?? base
    }()
    static var ok: Bool { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil }
    static var defaults: UserDefaults? { ok ? UserDefaults(suiteName: id) : nil }
}

/// Données affichées par les widgets (préparées par la page de l'appli).
struct WData: Codable {
    struct Last: Codable { var day: String?; var time: String?; var km: Double; var min: Int; var cons: Double?; var cost: Double?; var eco: Int?; var cutKm: Double?; var spark: [Double]? }
    struct Week: Codable { var km: Double; var n: Int; var eur: Double?; var L: Double?; var cutKm: Double?; var days: [Double]; var today: Int }
    var name: String?
    var range: Int?
    var left: Double?
    var pct: Double?
    var meas: Bool?
    var nextFill: String?
    var lock: Bool?
    var last: Last?
    var week: Week?
    var t: Double

    static func load() -> WData? {
        guard let s = LMGroup.defaults?.string(forKey: "wdata"), let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WData.self, from: d)
    }
    static let demo = WData(name: "La Mathias", range: 390, left: 37.2, pct: 0.74, meas: false, nextFill: "vers le 5 janv.", lock: true,
        last: Last(day: "Aujourd’hui", time: "11:38", km: 14.6, min: 32, cons: 8.6, cost: 2.14, eco: 84, cutKm: 2.3, spark: [6, 7, 5, 9, 8, 10, 7, 6, 9, 8, 11, 7]),
        week: Week(km: 86, n: 9, eur: 12.4, L: 6.7, cutKm: 7.1, days: [12, 24, 9, 30, 11, 0, 0], today: 4), t: 0)
}
