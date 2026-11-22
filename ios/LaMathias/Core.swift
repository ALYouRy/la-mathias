import Foundation

/// Réunit la connexion OBD, l'enregistreur de trajets et le pont vers la page web.
final class Core {
    static let shared = Core()
    let obd = OBD()
    lazy var rec = Recorder(obd: obd)
    weak var web: WebViewController?
    private var started = false

    func start() {
        if started { return }
        started = true
        rec.setup()
        obd.start()
    }

    /// Envoie un appel JavaScript à la page (si elle est affichée).
    func js(_ code: String) {
        DispatchQueue.main.async { self.web?.run(code) }
    }

    static func json(_ o: Any) -> String {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o), let s = String(data: d, encoding: .utf8) else { return "null" }
        return s
    }
}
