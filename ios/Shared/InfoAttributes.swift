import ActivityKit
import Foundation

/// Messages courts dans la Dynamic Island (réservoir au démarrage, trajet enregistré, OBD connecté, alertes…).
struct InfoAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var icon: String        // nom de symbole SF
        var title: String
        var sub: String
        var right: String
        var tone: String        // info, good, warn, bad
        var progress: Double?   // jauge 0…1 (réservoir)
    }
    var kind: String
}

enum LMInfo {
    static func rgb(_ tone: String) -> (Double, Double, Double) {
        switch tone {
        case "good": return (0.37, 0.89, 0.55)
        case "warn": return (1, 0.70, 0.25)
        case "bad": return (1, 0.33, 0.33)
        default: return (0, 0.9, 1)
        }
    }
    static func symbol(_ k: String) -> String {
        switch k {
        case "car": return "car.fill"
        case "check": return "checkmark.circle.fill"
        case "fuel": return "fuelpump.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "qr": return "qrcode"
        case "star": return "star.fill"
        case "wrench": return "wrench.and.screwdriver.fill"
        case "road": return "road.lanes"
        case "leaf": return "leaf.fill"
        case "moon": return "moon.fill"
        case "map": return "map.fill"
        case "pin": return "mappin.circle.fill"
        case "flag": return "flag.checkered"
        case "crown": return "crown.fill"
        case "feather": return "wind"
        case "bolt": return "bolt.fill"
        case "battery": return "minus.plus.batteryblock.fill"
        default: return "car.fill"
        }
    }
}
