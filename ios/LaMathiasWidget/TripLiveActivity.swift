import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LaMathiasWidgets: WidgetBundle {
    var body: some Widget {
        TripLiveActivity()
        InfoLiveActivity()
    }
}

private func col(_ s: TripAttributes.ContentState) -> Color {
    let c = LMFmt.rgb(s)
    return Color(red: c.0, green: c.1, blue: c.2)
}

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { ctx in
            TripStateView(s: ctx.state)
                .activityBackgroundTint(Color(red: 0.04, green: 0.03, blue: 0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            if s.standby == true { return standbyIsland(s) }
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(s.speed)").font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text(gearTxt(s)).font(.caption2).foregroundColor(.secondary)
                    }.padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(LMFmt.consText(s)).font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(col(s))
                        Text(s.cut ? "0 conso" : LMFmt.consUnit(s)).font(.caption2).foregroundColor(.secondary)
                    }.padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        HStack {
                            Text(LMFmt.n1(s.km) + " km")
                            Spacer()
                            Text("moy. " + (s.avg != nil ? LMFmt.n1(s.avg!) : "–"))
                            Spacer()
                            Text("\(s.minutes) min")
                            if let c = s.cost { Spacer(); Text(euro(c)) }
                        }.font(.system(size: 14, weight: .semibold, design: .rounded))
                        HStack {
                            if let r = s.rpm { Text("\(r) tr/min") }
                            Spacer()
                            if let ck = s.cutKm { Text(LMFmt.n1(ck) + " km à 0 L").foregroundColor(Color(red: 0.35, green: 0.89, blue: 0.55)) }
                            Spacer()
                            if let r = s.range { Text("autonomie \(r) km") }
                        }.font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7))
                    }.monospacedDigit().padding(.horizontal, 6)
                }
            } compactLeading: {
                Text("\(s.speed)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            } compactTrailing: {
                Text(LMFmt.consText(s)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(col(s))
            } minimal: {
                Text(LMFmt.consText(s)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(col(s))
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

private func gearTxt(_ s: TripAttributes.ContentState) -> String {
    if let g = s.gear { return "km/h · \(g)\(g == 1 ? "re" : "e")" }
    return "km/h"
}
private func euro(_ c: Double) -> String { String(format: "%.2f €", c).replacingOccurrences(of: ".", with: ",") }
private let green = Color(red: 0.35, green: 0.89, blue: 0.55)

/// Choisit l'affichage : petit format (CarPlay, Apple Watch) ou écran verrouillé.
struct TripStateView: View {
    let s: TripAttributes.ContentState
    @Environment(\.activityFamily) var family
    var body: some View {
        if s.standby == true { StandbyView(s: s, small: family == .small) }
        else if family == .small { CarPlayView(s: s) } else { LockScreenView(s: s) }
    }
}

private func standbyLine(_ s: TripAttributes.ContentState) -> String {
    if s.km <= 0 { return "Prête pour le prochain trajet" }
    var t: String = "Dernier trajet " + LMFmt.n1(s.km) + " km"
    if let a = s.avg { t += " · " + LMFmt.n1(a) + " L/100" }
    return t
}

/// 2.90 : widget « prêt » entre deux trajets (reste en place pour s'afficher sur CarPlay dès le départ)
private func standbyIsland(_ s: TripAttributes.ContentState) -> DynamicIsland {
    DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
            Label(s.left != nil ? LMFmt.n1(s.left!) + " L" : "La Mathias", systemImage: "fuelpump.fill").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(green).padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
            Text(s.range != nil ? "\(s.range!) km" : "prête").font(.system(size: 20, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(green).padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.bottom) {
            Text(standbyLine(s))
                .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7))
        }
    } compactLeading: {
        Image(systemName: "fuelpump.fill").foregroundColor(green)
    } compactTrailing: {
        Text(s.range != nil ? "\(s.range!)" : "OK").font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(green)
    } minimal: {
        Image(systemName: "fuelpump.fill").foregroundColor(green)
    }
}

struct StandbyView: View {
    let s: TripAttributes.ContentState
    let small: Bool
    private var lastTxt: String {
        var t: String = "Dernier trajet · " + LMFmt.n1(s.km) + " km"
        t += " · \(s.minutes) min"
        if let a = s.avg { t += " · " + LMFmt.n1(a) + " L/100" }
        if let c = s.cost { t += " · " + euro(c) }
        return t
    }
    var body: some View {
        VStack(alignment: .leading, spacing: small ? 3 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("La Mathias", systemImage: "car.fill").font(.system(size: small ? 14 : 16, weight: .heavy, design: .rounded))
                Spacer()
                Text("prête").font(.system(size: small ? 11 : 13, weight: .bold)).foregroundColor(green)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let r = s.range { Text("\(r)").font(.system(size: small ? 26 : 32, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(green); Text("km d’autonomie").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary) }
                Spacer(minLength: 4)
                if let l = s.left { Label(LMFmt.n1(l) + " L", systemImage: "fuelpump.fill").font(.system(size: 13, weight: .bold, design: .rounded)) }
            }.lineLimit(1).minimumScaleFactor(0.6)
            if s.km > 0 {
                Text(lastTxt)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, small ? 10 : 16).padding(.vertical, small ? 8 : 14)
        .foregroundColor(.white)
    }
}

/// 2.88 : vue CarPlay / Watch — vitesse et conso en grand, puis rapport, régime, moyenne, km, autonomie, km à 0 L.
struct CarPlayView: View {
    let s: TripAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.speed)").font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit()
                Text(s.gear != nil ? "km/h \(s.gear!)\(s.gear == 1 ? "re" : "e")" : "km/h").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Spacer(minLength: 2)
                Text(LMFmt.consText(s)).font(.system(size: 30, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(col(s))
                Text(s.cut ? "0 L" : LMFmt.consUnit(s)).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            }.lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 8) {
                if let r = s.rpm { Text("\(r) tr") }
                Text("moy " + (s.avg != nil ? LMFmt.n1(s.avg!) : "–"))
                Text(LMFmt.n1(s.km) + " km")
                Text("\(s.minutes) min")
            }.font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 8) {
                if let r = s.range { Label("\(r) km", systemImage: "fuelpump.fill") }
                if let ck = s.cutKm { Label(LMFmt.n1(ck) + " km", systemImage: "leaf.fill").foregroundColor(green) }
                if let c = s.cost { Text(euro(c)) }
            }.font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .foregroundColor(.white)
    }
}

struct LockScreenView: View {
    let s: TripAttributes.ContentState
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.speed)").font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text(gearTxt(s) + (s.rpm != nil ? " · \(s.rpm!) tr/min" : "")).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(LMFmt.consText(s)).font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(col(s))
                    Text(s.cut ? "injection coupée · 0 conso" : LMFmt.consUnit(s)).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack {
                Label(LMFmt.n1(s.km) + " km", systemImage: "car.fill")
                Spacer()
                Text("moy. " + (s.avg != nil ? LMFmt.n1(s.avg!) + " L/100" : "–"))
                Spacer()
                Text("\(s.minutes) min")
            }.font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(.white.opacity(0.85))
            HStack {
                if let r = s.range { Label("\(r) km", systemImage: "fuelpump.fill") }
                Spacer()
                if let ck = s.cutKm { Label(LMFmt.n1(ck) + " km à 0 L", systemImage: "leaf.fill").foregroundColor(green) }
                Spacer()
                if let c = s.cost { Text(euro(c)) }
            }.font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(.white.opacity(0.7))
        }
        .padding(16)
        .foregroundColor(.white)
    }
}
