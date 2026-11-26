import ActivityKit
import AVFoundation
import Foundation
import UIKit

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
    /// le module (extension) est-il bien installé ? SideStore peut le retirer.
    var hasExtension: Bool {
        guard let u = Bundle.main.builtInPlugInsURL, let l = try? FileManager.default.contentsOfDirectory(atPath: u.path) else { return false }
        return l.contains { $0.hasSuffix(".appex") }
    }
    var available: Bool { enabled && hasExtension }

    func start(_ s: TripAttributes.ContentState, since: Date) {
        if act != nil || !enabled { return }
        if let a = Activity<TripAttributes>.activities.first { act = a; return }
        act = try? Activity.request(attributes: TripAttributes(start: since), content: .init(state: s, staleDate: nil, relevanceScore: 100), pushType: nil)
    }

    private var lastTry = Date.distantPast
    /// 2.90 : essaie de lancer l'activité même appli en arrière-plan (au plus toutes les 20 s) ; iOS peut refuser.
    func tryStart(_ s: TripAttributes.ContentState, since: Date) {
        if running || !enabled { return }
        if Date().timeIntervalSince(lastTry) < 20 { return }
        lastTry = Date()
        start(s, since: since)
    }
    /// option « widget toujours prêt » (réglage de l'appli, activée par défaut)
    var keep: Bool { UserDefaults.standard.object(forKey: "keepAct") as? Bool ?? true }
    /// à l'ouverture de l'appli : s'il n'y a pas d'activité, on lance le widget « prêt »
    func ensureStandby(_ s: TripAttributes.ContentState) {
        if !keep || running || !enabled { return }
        start(s, since: Date())
    }
    /// fin de trajet : au lieu de fermer, le widget passe en « prêt » (garée) et reste pour le prochain départ
    func park(_ s: TripAttributes.ContentState, final f: TripAttributes.ContentState?) {
        if !keep { end(f); return }
        guard let a = act ?? Activity<TripAttributes>.activities.first else { return }
        act = a; lastState = s; last = Date()
        Task { await a.update(.init(state: s, staleDate: nil, relevanceScore: 100)) }
    }

    func update(_ s: TripAttributes.ContentState) {
        guard let a = act else { return }
        if s == lastState { return }
        if Date().timeIntervalSince(last) < 0.9 { return }
        last = Date()
        lastState = s
        Task { await a.update(.init(state: s, staleDate: Date().addingTimeInterval(180), relevanceScore: 100)) }
    }

    func end(_ s: TripAttributes.ContentState?) {
        let all = Activity<TripAttributes>.activities
        act = nil
        lastState = nil
        for a in all {
            Task { await a.end(s.map { .init(state: $0, staleDate: nil) }, dismissalPolicy: .after(Date().addingTimeInterval(10 * 60))) }
        }
    }

    // MARK: - Messages courts (remplacent l'ancienne « Dynamic Island » de la page)

    private var infoQueue: [(InfoAttributes.ContentState, Double)] = []
    private var infoAct: Activity<InfoAttributes>?
    private var infoBusy = false
    var lastErr = ""

    func info(_ s: InfoAttributes.ContentState, seconds: Double) {
        if !enabled { return }
        // 2.97 : pas de messages sur l'écran de la voiture (CarPlay) : là, seul le widget du trajet s'affiche
        if CarLink.connected { return }
        infoQueue.append((s, max(3, min(12, seconds))))
        if !infoBusy { nextInfo() }
    }

    private func nextInfo() {
        guard !infoQueue.isEmpty else { infoBusy = false; return }
        infoBusy = true
        let (s, sec) = infoQueue.removeFirst()
        for a in Activity<InfoAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        do { infoAct = try Activity.request(attributes: InfoAttributes(kind: s.icon), content: .init(state: s, staleDate: nil, relevanceScore: 1), pushType: nil); lastErr = "" }
        catch { infoAct = nil; lastErr = String(describing: error) }
        // si on quitte l'appli pendant le message, iOS laisse un peu de temps pour le refermer à l'heure
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg); bg = .invalid }
        DispatchQueue.main.asyncAfter(deadline: .now() + sec) { [weak self] in
            defer { if bg != .invalid { UIApplication.shared.endBackgroundTask(bg); bg = .invalid } }
            guard let self = self else { return }
            if let a = self.infoAct { Task { await a.end(nil, dismissalPolicy: .immediate) } }
            self.infoAct = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.nextInfo() }
        }
    }

    /// 2.97 : CarPlay vient de se connecter → on retire les messages et on (re)met le widget du trajet en avant
    func carConnected(_ s: TripAttributes.ContentState) {
        infoQueue.removeAll()
        for a in Activity<InfoAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
        infoAct = nil
        if let a = act ?? Activity<TripAttributes>.activities.first {
            act = a; lastState = s; last = Date()
            Task { await a.update(.init(state: s, staleDate: nil, relevanceScore: 100)) }
        } else { tryStart(s, since: Date()) }
    }

    // MARK: - Diagnostic (bouton « Tester » dans Réglages)

    func diagnose() -> [String: Any] {
        var o: [String: Any] = [:]
        let info = ActivityAuthorizationInfo()
        o["enabled"] = info.areActivitiesEnabled
        let plug = Bundle.main.builtInPlugInsURL
        let exts = (try? FileManager.default.contentsOfDirectory(atPath: plug?.path ?? "")) ?? []
        o["ext"] = exts.joined(separator: ",")
        let s = InfoAttributes.ContentState(icon: "check", title: "Test Dynamic Island", sub: "Si tu vois ce message, tout marche", right: "OK", tone: "good", progress: 0.7)
        do {
            let a = try Activity.request(attributes: InfoAttributes(kind: "test"), content: .init(state: s, staleDate: nil), pushType: nil)
            o["ok"] = true
            o["count"] = Activity<InfoAttributes>.activities.count
            var bg = UIBackgroundTaskIdentifier.invalid
            bg = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(bg); bg = .invalid }
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                Task { await a.end(nil, dismissalPolicy: .immediate) }
                if bg != .invalid { UIApplication.shared.endBackgroundTask(bg); bg = .invalid }
            }
        } catch {
            o["ok"] = false
            o["err"] = String(describing: error)
        }
        return o
    }
}


/// 2.97 : l'iPhone est-il branché sur CarPlay ? (sortie audio « voiture »)
enum CarLink {
    static var connected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .carAudio }
    }
}
