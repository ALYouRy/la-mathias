import UIKit
import MapKit
import SwiftUI
import Charts

/// 2.94 : revue d'un trajet sur la carte Apple Plans, avec le tracé GPS tel que l'iPhone l'a enregistré
/// (l'iPhone recale déjà sa position sur les routes d'Apple en mode voiture : sur la carte Plans, le tracé tombe pile sur la route).
final class TripMapViewController: UIViewController, MKMapViewDelegate {
    var pts: [[Double]] = []          // [lat, lon, conso L/100 ou -1, vitesse km/h ou -1]
    var titleText = ""
    var subText = ""
    var stats: [String: Any] = [:]
    var t0: Double = 0
    private let map = MKMapView()
    private var colors: [UIColor] = []
    private var locs: [CGFloat] = []
    private var dists: [Double] = []
    private var coords: [CLLocationCoordinate2D] = []
    private let cursor = MKPointAnnotation()

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1)
        overrideUserInterfaceStyle = .dark
        map.translatesAutoresizingMaskIntoConstraints = false
        map.delegate = self
        let cfg = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        cfg.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = cfg
        map.showsCompass = true
        view.addSubview(map)
        buildTrack()
        let panel = UIHostingController(rootView: TripPanel(stats: stats, dists: dists, pts: pts, onScrub: { [weak self] i in self?.moveCursor(i) }, onMore: { [weak self] in self?.more() }))
        panel.view.backgroundColor = .clear
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(panel); view.addSubview(panel.view); panel.didMove(toParent: self)
        NSLayoutConstraint.activate([
            map.topAnchor.constraint(equalTo: view.topAnchor), map.leadingAnchor.constraint(equalTo: view.leadingAnchor), map.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            map.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), panel.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        buildHeader()
        fit(bottom: 330)
    }

    private func buildHeader() {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18; card.clipsToBounds = true
        view.addSubview(card)
        let t = UILabel(), s = UILabel()
        t.text = titleText; t.font = .systemFont(ofSize: 19, weight: .heavy); t.textColor = .white
        s.text = subText; s.font = .systemFont(ofSize: 13, weight: .semibold); s.textColor = UIColor(white: 1, alpha: 0.65)
        let st = UIStackView(arrangedSubviews: [t, s]); st.axis = .vertical; st.spacing = 2
        st.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(st)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)), for: .normal)
        close.tintColor = .white; close.backgroundColor = UIColor(white: 1, alpha: 0.14); close.layer.cornerRadius = 18
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTap), for: .touchUpInside)
        card.contentView.addSubview(close)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            st.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16), st.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            st.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12), st.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -10),
            close.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -12), close.centerYAnchor.constraint(equalTo: card.contentView.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 36), close.heightAnchor.constraint(equalToConstant: 36)])
    }

    @objc private func closeTap() { dismiss(animated: true) }
    private func more() {
        let t = t0
        dismiss(animated: true) { Core.shared.js("window.LMN&&LMN.webMap&&LMN.webMap(\(Int64(t)))") }
    }

    private func buildTrack() {
        var tot = 0.0
        for p in pts where p.count >= 2 {
            let c = CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
            if let l = coords.last { tot += CLLocation(latitude: l.latitude, longitude: l.longitude).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) }
            coords.append(c); dists.append(tot)
            colors.append(GPSViewController.color(p.count > 2 && p[2] >= 0 ? p[2] : nil))
        }
        guard coords.count >= 2 else { return }
        locs = dists.map { CGFloat($0 / max(1, tot)) }
        map.addOverlay(MKPolyline(coordinates: coords, count: coords.count), level: .aboveRoads)
        let a = MKPointAnnotation(); a.coordinate = coords.first!; a.title = "Départ"
        let b = MKPointAnnotation(); b.coordinate = coords.last!; b.title = "Arrivée"
        cursor.coordinate = coords.first!; cursor.title = "•"
        map.addAnnotations([a, b])
    }

    private func fit(bottom: CGFloat) {
        guard coords.count >= 2 else { return }
        let pl = MKPolyline(coordinates: coords, count: coords.count)
        map.setVisibleMapRect(pl.boundingMapRect, edgePadding: UIEdgeInsets(top: 120, left: 36, bottom: bottom, right: 36), animated: false)
    }

    private func moveCursor(_ i: Int?) {
        guard let i = i, i >= 0, i < coords.count else { map.removeAnnotation(cursor); return }
        if !map.annotations.contains(where: { $0 === cursor }) { map.addAnnotation(cursor) }
        cursor.coordinate = coords[i]
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let pl = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let r = MKGradientPolylineRenderer(polyline: pl)
        r.setColors(colors, locations: locs)
        r.lineWidth = 6; r.lineCap = .round; r.lineJoin = .round
        return r
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let a = annotation as? MKPointAnnotation else { return nil }
        if a === cursor {
            let v = MKAnnotationView(annotation: a, reuseIdentifier: "c")
            let d = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
            d.backgroundColor = .white; d.layer.cornerRadius = 9; d.layer.borderWidth = 4; d.layer.borderColor = UIColor(red: 0, green: 0.9, blue: 1, alpha: 1).cgColor
            v.addSubview(d); v.frame = d.frame
            return v
        }
        let v = MKMarkerAnnotationView(annotation: a, reuseIdentifier: "p")
        v.markerTintColor = a.title == "Départ" ? UIColor(red: 0.2, green: 0.82, blue: 0.48, alpha: 1) : UIColor(red: 0.94, green: 0.33, blue: 0.31, alpha: 1)
        v.glyphImage = UIImage(systemName: a.title == "Départ" ? "flag.fill" : "flag.checkered")
        return v
    }
}

/// Panneau du bas : chiffres du trajet + graphe vitesse / conso (glisse le doigt pour suivre sur la carte)
struct TripPanel: View {
    let stats: [String: Any]
    let dists: [Double]
    let pts: [[Double]]
    let onScrub: (Int?) -> Void
    let onMore: () -> Void
    @State private var sel: Int? = nil

    private struct P: Identifiable { let id: Int; let km: Double; let v: Double?; let c: Double? }
    private var series: [P] {
        var o: [P] = []
        let n = min(dists.count, pts.count)
        let step = max(1, n / 220)
        var i = 0
        while i < n {
            let p = pts[i]
            o.append(P(id: i, km: dists[i] / 1000, v: p.count > 3 && p[3] >= 0 ? p[3] : nil, c: p.count > 2 && p[2] >= 0 ? min(30, p[2]) : nil))
            i += step
        }
        return o
    }
    private func s(_ k: String) -> String? { stats[k] as? String }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip(s("cons") ?? "–", "L/100", Color(red: 0, green: 0.9, blue: 1))
                chip(s("cost") ?? "–", "dépensé", Color(red: 1, green: 0.69, blue: 0.13))
                chip(s("eco") ?? "–", "éco", Color(red: 0.2, green: 0.82, blue: 0.48))
                chip(s("vmax") ?? "–", "km/h max", .white)
            }
            if let i = sel, i < pts.count, i < dists.count {
                let p = pts[i]
                Text(String(format: "%.1f km", dists[i] / 1000).replacingOccurrences(of: ".", with: ",")
                     + (p.count > 3 && p[3] >= 0 ? " · \(Int(p[3])) km/h" : "")
                     + (p.count > 2 && p[2] >= 0 ? " · " + String(format: "%.1f L/100", p[2]).replacingOccurrences(of: ".", with: ",") : ""))
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
            } else {
                Text("Glisse le doigt sur le graphe pour suivre le trajet").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.55))
            }
            chart.frame(height: 110)
            Button(action: onMore) {
                Label("Rejouer, cartes néon et détails", systemImage: "play.circle.fill").font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1)))
            }.foregroundColor(.white)
        }
        .padding(16).padding(.bottom, 20)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.05, green: 0.04, blue: 0.13).opacity(0.96)).ignoresSafeArea(edges: .bottom))
    }

    private var chart: some View {
        let data = series
        return Chart {
            ForEach(data) { p in
                if let c = p.c { AreaMark(x: .value("km", p.km), y: .value("conso", c * 3)).foregroundStyle(Color.orange.opacity(0.28)).interpolationMethod(.monotone) }
            }
            ForEach(data) { p in
                if let v = p.v { LineMark(x: .value("km", p.km), y: .value("vitesse", v), series: .value("s", "v")).foregroundStyle(.white).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone) }
            }
            if let i = sel, i < dists.count { RuleMark(x: .value("km", dists[i] / 1000)).foregroundStyle(Color(red: 0, green: 0.9, blue: 1)) }
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel().foregroundStyle(Color.white.opacity(0.5)) } }
        .chartOverlay { proxy in
            GeometryReader { g in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard let km: Double = proxy.value(atX: v.location.x - g[proxy.plotAreaFrame].origin.x) else { return }
                            let m = km * 1000
                            var best = 0
                            for (j, d) in dists.enumerated() where abs(d - m) < abs(dists[best] - m) { best = j }
                            sel = best; onScrub(best)
                        })
            }
        }
    }

    private func chip(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundColor(c).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.55))
        }.frame(maxWidth: .infinity).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }
}
