import ActivityKit
import Foundation

/// Activité en direct (Dynamic Island + écran verrouillé) pendant un trajet.
/// iOS ne permet de la lancer que quand l'appli est ouverte ; ensuite elle se met à jour même téléphone verrouillé.
final class LiveAct {
    static let shared = LiveAct()
    private var act: Activity<TripAttributes>?
    private var last = Date.distantPast
    private var lastState: TripAttributes.ContentState?

    var running: Bool {
        if act == nil { act = Activity<TripAttributes>.activities.first }
        return act != nil
    }
    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(_ s: TripAttributes.ContentState, since: Date) {
        if act != nil || !enabled { return }
        if let a = Activity<TripAttributes>.activities.first { act = a; return }
        act = try? Activity.request(attributes: TripAttributes(start: since), content: .init(state: s, staleDate: nil), pushType: nil)
    }

    func update(_ s: TripAttributes.ContentState) {
        guard let a = act else { return }
        if s == lastState { return }
        if Date().timeIntervalSince(last) < 1.5 { return }
        last = Date()
        lastState = s
        Task { await a.update(.init(state: s, staleDate: Date().addingTimeInterval(180))) }
    }

    func end(_ s: TripAttributes.ContentState?) {
        let all = Activity<TripAttributes>.activities
        act = nil
        lastState = nil
        for a in all {
            Task { await a.end(s.map { .init(state: $0, staleDate: nil) }, dismissalPolicy: .after(Date().addingTimeInterval(10 * 60))) }
        }
    }
}
