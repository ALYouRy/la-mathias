import Foundation
import AppIntents

/// 2.92 : bouton « Démarrer » du widget (CarPlay, écran verrouillé, Dynamic Island).
/// iOS exécute ce bouton dans l'appli (en arrière-plan, sans l'ouvrir) : l'appli relance le boîtier OBD
/// et démarre l'enregistrement dès que le moteur tourne, même sans attendre 5 km/h.
enum LMHook { static var start: (() -> Void)? }

@available(iOS 17.0, *)
struct StartTripIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Démarrer le trajet"
    static var description = IntentDescription("Lance l'enregistrement du trajet La Mathias.")
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        await MainActor.run { LMHook.start?() }
        return .result()
    }
}
