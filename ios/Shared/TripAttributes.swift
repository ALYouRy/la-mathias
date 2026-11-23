import ActivityKit
import Foundation

/// Données du trajet affichées dans la Dynamic Island et sur l'écran verrouillé.
struct TripAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var speed: Int
        var cons: Double?      // L/100 (nil à l'arrêt)
        var lph: Double?       // L/h
        var avg: Double?       // moyenne du trajet L/100
        var km: Double
        var minutes: Int
        var cut: Bool
        var gear: Int?
        var cost: Double?
    }
    var start: Date
}

enum LMFmt {
    static func n1(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
    static func consText(_ s: TripAttributes.ContentState) -> String {
        if s.cut { return "0" }
        if let c = s.cons { return n1(min(c, 99)) }
        if let l = s.lph { return n1(l) }
        return "–"
    }
    static func consUnit(_ s: TripAttributes.ContentState) -> String { s.cut || s.cons != nil ? "L/100" : "L/h" }
    /// vert → jaune → rouge selon la conso (comme l'appli)
    static func rgb(_ s: TripAttributes.ContentState) -> (Double, Double, Double) {
        if s.cut { return (0.35, 0.89, 0.55) }
        guard let c = s.cons else { return (0.75, 0.75, 0.85) }
        let t = max(0, min(1, (c - 4.5) / 5.5))
        if t < 0.5 { let k = t / 0.5; return (0.35 + 0.65 * k, 0.89 - 0.07 * k, 0.55 - 0.4 * k) }
        let k = (t - 0.5) / 0.5
        return (1, 0.82 - 0.52 * k, 0.15 + 0.1 * k)
    }
}
