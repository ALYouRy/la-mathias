import WidgetKit
import SwiftUI

// 2.91 : widgets de l'écran d'accueil et de l'écran verrouillé

struct WEntry: TimelineEntry { let date: Date; let d: WData?; let preview: Bool }

struct WProvider: TimelineProvider {
    func placeholder(in context: Context) -> WEntry { WEntry(date: Date(), d: .demo, preview: true) }
    func getSnapshot(in context: Context, completion: @escaping (WEntry) -> Void) {
        completion(WEntry(date: Date(), d: context.isPreview ? (WData.load() ?? .demo) : WData.load(), preview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WEntry>) -> Void) {
        completion(Timeline(entries: [WEntry(date: Date(), d: WData.load(), preview: false)], policy: .after(Date().addingTimeInterval(3600))))
    }
}

// MARK: - Couleurs et petits éléments

private let wBg = Color(red: 0.047, green: 0.039, blue: 0.122)
private let wGreen = Color(red: 0.20, green: 0.82, blue: 0.48)
private let wCyan = Color(red: 0.0, green: 0.90, blue: 1.0)
private let wAmber = Color(red: 1.0, green: 0.69, blue: 0.13)
private let wTrack = Color(red: 0.165, green: 0.157, blue: 0.25)
private let wSub = Color.white.opacity(0.6)

private func n1(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
private func eur(_ v: Double) -> String { String(format: "%.2f €", v).replacingOccurrences(of: ".", with: ",") }
private func costEco(_ l: WData.Last, cut: Bool) -> String {
    var a: [String] = []
    if let c = l.cost { a.append(eur(c)) }
    if let e = l.eco { a.append("éco \(e)") }
    if cut, let k = l.cutKm { a.append(n1(k) + " km à 0 L") }
    return a.joined(separator: " · ")
}
private func fuelCol(_ p: Double?) -> Color { guard let p = p else { return wGreen }; return p < 0.15 ? .red : p < 0.3 ? wAmber : wGreen }

private struct Bar: View {
    let p: Double; let c: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(wTrack)
                Capsule().fill(c).frame(width: max(6, g.size.width * CGFloat(min(1, max(0, p)))))
            }
        }.frame(height: 6)
    }
}

private struct Ring: View {
    let p: Double; let c: Color; var w: CGFloat = 9
    var body: some View {
        ZStack {
            Circle().stroke(wTrack, lineWidth: w)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, p)))).stroke(c, style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(-90))
        }
    }
}

private struct Spark: View {
    let v: [Double]; let c: Color
    var body: some View {
        GeometryReader { g in
            if v.count > 1, let mn = v.min(), let mx = v.max() {
                let rg = max(0.001, mx - mn)
                Path { p in
                    for (i, x) in v.enumerated() {
                        let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(v.count - 1), y: g.size.height - 2 - CGFloat((x - mn) / rg) * (g.size.height - 4))
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }.stroke(c, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct Empty: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.fill").font(.title2).foregroundColor(wCyan)
            Text("Ouvre La Mathias").font(.system(size: 13, weight: .bold, design: .rounded))
            Text("pour afficher tes infos").font(.system(size: 11)).foregroundColor(wSub)
        }.multilineTextAlignment(.center)
    }
}

private extension View {
    @ViewBuilder func wBackground() -> some View {
        if #available(iOS 17.0, *) { self.containerBackground(wBg, for: .widget) } else { self.padding().background(wBg) }
    }
}

// MARK: - 1 · Réservoir (petit, barre)

struct FuelBarView: View {
    let e: WEntry
    var body: some View {
        Group {
            if let d = e.d, d.range != nil || d.left != nil {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Réservoir", systemImage: "fuelpump.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                    Spacer(minLength: 6)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(d.range.map { "\($0)" } ?? "–").font(.system(size: 36, weight: .heavy, design: .rounded)).foregroundColor(fuelCol(d.pct)).minimumScaleFactor(0.6)
                        Text("km").font(.system(size: 12, weight: .semibold)).foregroundColor(wSub)
                    }
                    Text(d.left.map { n1($0) + " L restants" } ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(wSub).padding(.bottom, 8)
                    Bar(p: d.pct ?? 0, c: fuelCol(d.pct))
                    if let nf = d.nextFill, !nf.isEmpty { Text("Plein " + nf).font(.system(size: 11, weight: .medium)).foregroundColor(wSub).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 7) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else { Empty() }
        }.foregroundColor(.white).widgetURL(URL(string: "lamathias://voiture")).wBackground()
    }
}

struct FuelBarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.fuel", provider: WProvider()) { FuelBarView(e: $0) }
            .configurationDisplayName("Réservoir").description("Autonomie, litres restants et prochain plein.")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - 1b · Réservoir (petit, anneau)

struct FuelRingView: View {
    let e: WEntry
    var body: some View {
        Group {
            if let d = e.d, d.range != nil || d.left != nil {
                VStack(spacing: 6) {
                    ZStack {
                        Ring(p: d.pct ?? 0, c: fuelCol(d.pct), w: 10)
                        VStack(spacing: -2) {
                            Text(d.range.map { "\($0)" } ?? "–").font(.system(size: 28, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6)
                            Text("km").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                        }
                    }.frame(width: 100, height: 100)
                    Text((d.left.map { n1($0) + " L" } ?? "") + (d.pct.map { " · \(Int(($0 * 100).rounded())) %" } ?? "")).font(.system(size: 12, weight: .semibold)).foregroundColor(wSub)
                }
            } else { Empty() }
        }.foregroundColor(.white).widgetURL(URL(string: "lamathias://voiture")).wBackground()
    }
}

struct FuelRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.fuelring", provider: WProvider()) { FuelRingView(e: $0) }
            .configurationDisplayName("Réservoir (anneau)").description("Le niveau du réservoir en anneau.")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - 2 · Dernier trajet (petit)

struct LastTripView: View {
    let e: WEntry
    var body: some View {
        Group {
            if let l = e.d?.last {
                VStack(alignment: .leading, spacing: 0) {
                    Label("Dernier trajet" + (l.time.map { " · " + $0 } ?? ""), systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(l.cons.map { n1($0) } ?? n1(l.km)).font(.system(size: 32, weight: .heavy, design: .rounded)).foregroundColor(wCyan)
                        Text(l.cons != nil ? "L/100" : "km").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                    }
                    Text(n1(l.km) + " km · \(l.min) min").font(.system(size: 13, weight: .bold, design: .rounded))
                    if let sp = l.spark, sp.count > 2 { Spark(v: sp, c: wCyan).frame(height: 22).padding(.vertical, 4) }
                    Text(costEco(l, cut: false)).font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else { Empty() }
        }.foregroundColor(.white).widgetURL(URL(string: "lamathias://trajets")).wBackground()
    }
}

struct LastTripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.last", provider: WProvider()) { LastTripView(e: $0) }
            .configurationDisplayName("Dernier trajet").description("Conso, km, prix et courbe du dernier trajet.")
            .supportedFamilies([.systemSmall])
    }
}

// MARK: - 3 · Tableau de bord (moyen)

struct DashView: View {
    let e: WEntry
    var body: some View {
        Group {
            if let d = e.d {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        Label("Autonomie", systemImage: "fuelpump.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                        Spacer(minLength: 4)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(d.range.map { "\($0)" } ?? "–").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundColor(fuelCol(d.pct)).minimumScaleFactor(0.6)
                            Text("km").font(.system(size: 12, weight: .semibold)).foregroundColor(wSub)
                        }
                        Text(d.left.map { n1($0) + " L" } ?? "").font(.system(size: 12, weight: .semibold)).foregroundColor(wSub).padding(.bottom, 8)
                        Bar(p: d.pct ?? 0, c: fuelCol(d.pct))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(wTrack).frame(width: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dernier trajet").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                        if let l = d.last {
                            Text(n1(l.km) + " km · \(l.min) min").font(.system(size: 13, weight: .bold, design: .rounded)).padding(.top, 4)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(l.cons.map { n1($0) } ?? "–").font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundColor(wCyan)
                                Text("L/100").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                            }
                            if let sp = l.spark, sp.count > 2 { Spark(v: sp, c: wCyan).frame(height: 20) }
                            Text(costEco(l, cut: true))
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(wSub).lineLimit(1).minimumScaleFactor(0.7)
                        } else { Text("Aucun trajet").font(.system(size: 13)).foregroundColor(wSub).padding(.top, 6) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else { Empty() }
        }.foregroundColor(.white).widgetURL(URL(string: "lamathias://voiture")).wBackground()
    }
}

struct DashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.dash", provider: WProvider()) { DashView(e: $0) }
            .configurationDisplayName("Tableau de bord").description("Réservoir et dernier trajet côte à côte.")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - 4 · Ma semaine (moyen)

private struct WeekBars: View {
    let w: WData.Week
    var body: some View {
        let mx = max(1, w.days.max() ?? 1)
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3).fill(i == w.today ? wCyan : Color(red: 0.18, green: 0.17, blue: 0.33))
                        .frame(height: max(3, CGFloat((i < w.days.count ? w.days[i] : 0) / mx) * 34))
                    Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.system(size: 9, weight: .semibold)).foregroundColor(i == w.today ? wCyan : wSub)
                }.frame(maxWidth: .infinity)
            }
        }.frame(height: 48, alignment: .bottom)
    }
}

struct WeekView: View {
    let e: WEntry
    var body: some View {
        Group {
            if let w = e.d?.week {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cette semaine").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                    HStack(alignment: .top) {
                        stat(n1(w.km), "km", "\(w.n) trajet" + (w.n > 1 ? "s" : ""), .white)
                        Spacer()
                        stat(w.eur.map { n1($0) } ?? "–", "€", w.L.map { n1($0) + " L" } ?? "", wAmber)
                        Spacer()
                        stat(n1(w.cutKm ?? 0), "km", "à 0 L/100", wGreen)
                    }
                    WeekBars(w: w)
                }
            } else { Empty() }
        }.foregroundColor(.white).widgetURL(URL(string: "lamathias://bilan")).wBackground()
    }
    private func stat(_ v: String, _ u: String, _ s: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(v).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(c).minimumScaleFactor(0.6)
                Text(u).font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
            }
            Text(s).font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
        }
    }
}

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.week", provider: WProvider()) { WeekView(e: $0) }
            .configurationDisplayName("Ma semaine").description("Km, argent dépensé et km roulés à 0 L/100 de la semaine.")
            .supportedFamilies([.systemMedium])
    }
}

// MARK: - 5 · Tout-en-un (grand)

struct AllView: View {
    let e: WEntry
    var body: some View {
        Group {
            if let d = e.d {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Label(d.name ?? "La Mathias", systemImage: "car.fill").font(.system(size: 12, weight: .bold)).foregroundColor(wSub)
                        Spacer()
                        if let lk = d.lock { Text(lk ? "verrouillée" : "ouverte").font(.system(size: 11, weight: .bold)).foregroundColor(lk ? wGreen : wAmber) }
                    }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(d.range.map { "\($0)" } ?? "–").font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundColor(fuelCol(d.pct))
                                Text("km").font(.system(size: 13, weight: .semibold)).foregroundColor(wSub)
                            }
                            Text(fuelLine(d))
                                .font(.system(size: 12, weight: .semibold)).foregroundColor(wSub)
                        }
                        Spacer()
                        Ring(p: d.pct ?? 0, c: fuelCol(d.pct), w: 8).frame(width: 54, height: 54)
                    }.padding(.top, 8)
                    Rectangle().fill(wTrack).frame(height: 1).padding(.vertical, 10)
                    if let l = d.last {
                        Text(lastHead(l)).font(.system(size: 11, weight: .semibold)).foregroundColor(wSub)
                        HStack {
                            Text(n1(l.km) + " km"); Spacer()
                            Text(l.cons.map { n1($0) + " L/100" } ?? "–").foregroundColor(wCyan); Spacer()
                            Text(l.cost.map { eur($0) } ?? "–"); Spacer()
                            Text(l.eco.map { "éco \($0)" } ?? "")
                        }.font(.system(size: 13, weight: .bold, design: .rounded)).padding(.top, 5)
                        if let sp = l.spark, sp.count > 2 { Spark(v: sp, c: wCyan).frame(height: 30).padding(.top, 6) }
                    } else { Text("Aucun trajet pour l’instant").font(.system(size: 13)).foregroundColor(wSub) }
                    Rectangle().fill(wTrack).frame(height: 1).padding(.vertical, 10)
                    if let w = d.week {
                        HStack {
                            Text("Semaine").font(.system(size: 11, weight: .semibold)).foregroundColor(wSub); Spacer()
                            Text(n1(w.km) + " km"); Spacer()
                            Text(w.eur.map { eur($0) } ?? "–").foregroundColor(wAmber); Spacer()
                            Text(n1(w.cutKm ?? 0) + " km à 0 L").foregroundColor(wGreen)
                        }.font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Link(destination: URL(string: "lamathias://conduite")!) { chip("Conduite", "steeringwheel", wCyan) }
                        Link(destination: URL(string: "lamathias://trajets")!) { chip("Trajets", "map", .white) }
                    }
                }
            } else { Empty() }
        }.foregroundColor(.white).widgetURL(URL(string: "lamathias://voiture")).wBackground()
    }
    private func fuelLine(_ d: WData) -> String {
        var a: [String] = []
        if let l = d.left { a.append(n1(l) + " L") }
        if let nf = d.nextFill, !nf.isEmpty { a.append("plein " + nf) }
        return a.joined(separator: " · ")
    }
    private func lastHead(_ l: WData.Last) -> String {
        var a: [String] = []
        if let x = l.day { a.append(x) }
        if let x = l.time { a.append(x) }
        return a.isEmpty ? "Dernier trajet" : "Dernier trajet · " + a.joined(separator: " ")
    }
    private func chip(_ t: String, _ i: String, _ c: Color) -> some View {
        Label(t, systemImage: i).font(.system(size: 13, weight: .bold)).foregroundColor(c)
            .frame(maxWidth: .infinity).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.11, green: 0.10, blue: 0.23)))
    }
}

struct AllWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.all", provider: WProvider()) { AllView(e: $0) }
            .configurationDisplayName("La Mathias").description("Voiture, réservoir, dernier trajet, semaine et raccourcis.")
            .supportedFamilies([.systemLarge])
    }
}

// MARK: - 6 · Écran verrouillé

struct LockView: View {
    let e: WEntry
    @Environment(\.widgetFamily) var family
    private var rangeTxt: String {
        guard let r = e.d?.range else { return "–" }
        return "\(r)"
    }
    private var line1: String {
        var t: String = e.d?.range.map { "\($0) km" } ?? "La Mathias"
        if let l = e.d?.left { t += " · " + n1(l) + " L" }
        return t
    }
    private var line2: String? {
        guard let l = e.d?.last else { return nil }
        var t: String = "Dernier trajet "
        if let c = l.cons { t += n1(c) + " L/100" } else { t += n1(l.km) + " km" }
        if let c = l.cost { t += " · " + eur(c) }
        return t
    }
    private var pct: Double { e.d?.pct ?? 0 }
    var body: some View {
        content.widgetURL(URL(string: "lamathias://voiture")).wLockBackground()
    }
    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryInline:
            Label(line1, systemImage: "fuelpump.fill")
        default:
            rect
        }
    }
    private var circular: some View {
        Gauge(value: pct) {
            Image(systemName: "fuelpump.fill")
        } currentValueLabel: {
            Text(rangeTxt).font(.system(size: 15, weight: .bold, design: .rounded))
        }.gaugeStyle(.accessoryCircular)
    }
    private var rect: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(line1, systemImage: "fuelpump.fill").font(.system(size: 15, weight: .bold, design: .rounded))
            if let l2 = line2 {
                Text(l2).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Gauge(value: pct) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
        }
    }
}

private extension View {
    @ViewBuilder func wLockBackground() -> some View {
        if #available(iOS 17.0, *) { self.containerBackground(.clear, for: .widget) } else { self }
    }
}

struct LockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lm.lock", provider: WProvider()) { LockView(e: $0) }
            .configurationDisplayName("Réservoir").description("Autonomie et dernier trajet sur l’écran verrouillé.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
