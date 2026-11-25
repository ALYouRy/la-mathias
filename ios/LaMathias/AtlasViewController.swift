import UIKit
import MapKit

/// 2.95 : toutes les cartes de l'appli sur Apple Plans, avec le GPS de l'iPhone tel quel.
/// Modes : « Dévoilé » (brouillard levé le long de tes trajets), « Passages » (tous tes trajets), « Zones » (conso / attente).
final class AtlasViewController: UIViewController, MKMapViewDelegate {
    struct Spot { let c: CLLocationCoordinate2D; let col: UIColor; let lab: String; let rank: Int }
    var traces: [[CLLocationCoordinate2D]] = []
    var counts: [Int] = []
    var spots: [Spot] = []
    var spotTitle = ""
    var mode = "fog"
    var fogKm = ""
    private let map = MKMapView()
    private let seg = UISegmentedControl(items: ["Dévoilé", "Passages"])
    private let sub = UILabel()
    private var fog: FogOverlay?

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
        map.showsUserLocation = true
        view.addSubview(map)
        NSLayoutConstraint.activate([map.topAnchor.constraint(equalTo: view.topAnchor), map.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     map.leadingAnchor.constraint(equalTo: view.leadingAnchor), map.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        buildHeader()
        apply()
        fitAll()
    }

    private func buildHeader() {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18; card.clipsToBounds = true
        view.addSubview(card)
        let t = UILabel()
        t.text = mode == "spots" ? spotTitle : "Ma carte"
        t.font = .systemFont(ofSize: 19, weight: .heavy); t.textColor = .white
        sub.font = .systemFont(ofSize: 13, weight: .semibold); sub.textColor = UIColor(white: 1, alpha: 0.65); sub.numberOfLines = 2
        let st = UIStackView(arrangedSubviews: [t, sub]); st.axis = .vertical; st.spacing = 2
        if mode != "spots" {
            seg.selectedSegmentIndex = mode == "pass" ? 1 : 0
            seg.addTarget(self, action: #selector(segChanged), for: .valueChanged)
            st.addArrangedSubview(seg); st.setCustomSpacing(10, after: sub)
        }
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
            st.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12), st.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -10),
            close.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -12), close.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 36), close.heightAnchor.constraint(equalToConstant: 36)])
    }

    @objc private func closeTap() { dismiss(animated: true) }
    @objc private func segChanged() { mode = seg.selectedSegmentIndex == 1 ? "pass" : "fog"; apply() }

    private func apply() {
        map.removeOverlays(map.overlays)
        map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
        switch mode {
        case "spots":
            sub.text = "Touche un rond pour le détail"
            for s in spots {
                let c = MKCircle(center: s.c, radius: 90); c.title = "spot"
                map.addOverlay(c, level: .aboveRoads)
                let a = MKPointAnnotation(); a.coordinate = s.c; a.title = "\(s.rank). " + s.lab
                map.addAnnotation(a)
            }
        case "pass":
            sub.text = "\(traces.count) trajet" + (traces.count > 1 ? "s" : "") + " · plus c'est lumineux, plus tu y passes"
            for (i, t) in traces.enumerated() where t.count >= 2 {
                let p = MKPolyline(coordinates: t, count: t.count); p.title = "pass"; p.subtitle = "\(i < counts.count ? counts[i] : 1)"
                map.addOverlay(p, level: .aboveRoads)
            }
        default:
            sub.text = fogKm.isEmpty ? "Le brouillard se lève là où tu as roulé" : fogKm
            let f = FogOverlay(traces: traces)
            fog = f
            map.addOverlay(f, level: .aboveLabels)
        }
    }

    private func fitAll() {
        var r = MKMapRect.null
        if mode == "spots" { for s in spots { let p = MKMapPoint(s.c); r = r.union(MKMapRect(x: p.x - 400, y: p.y - 400, width: 800, height: 800)) } }
        else { for t in traces { for c in t { let p = MKMapPoint(c); r = r.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1)) } } }
        if !r.isNull { map.setVisibleMapRect(r, edgePadding: UIEdgeInsets(top: 170, left: 30, bottom: 50, right: 30), animated: false) }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let f = overlay as? FogOverlay { return FogRenderer(overlay: f) }
        if let c = overlay as? MKCircle {
            let r = MKCircleRenderer(circle: c)
            let col = spots.first(where: { abs($0.c.latitude - c.coordinate.latitude) < 1e-7 && abs($0.c.longitude - c.coordinate.longitude) < 1e-7 })?.col ?? .systemOrange
            r.fillColor = col.withAlphaComponent(0.35); r.strokeColor = col; r.lineWidth = 2
            return r
        }
        if let p = overlay as? MKPolyline {
            let r = MKPolylineRenderer(polyline: p)
            r.strokeColor = UIColor(red: 0, green: 0.9, blue: 1, alpha: 0.45)
            r.lineWidth = 4; r.lineCap = .round; r.lineJoin = .round
            return r
        }
        return MKOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let a = annotation as? MKPointAnnotation else { return nil }
        let v = MKMarkerAnnotationView(annotation: a, reuseIdentifier: "s")
        v.canShowCallout = true
        v.markerTintColor = UIColor(red: 0.95, green: 0.45, blue: 0.2, alpha: 1)
        v.glyphText = a.title.flatMap { $0.split(separator: ".").first.map(String.init) }
        return v
    }
}

/// Brouillard sur toute la carte, effacé le long des trajets (≈ 60 m de large)
final class FogOverlay: NSObject, MKOverlay {
    let traces: [[MKMapPoint]]
    let boundingMapRect: MKMapRect = .world
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    init(traces t: [[CLLocationCoordinate2D]]) { traces = t.map { $0.map { MKMapPoint($0) } } }
}

final class FogRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let f = overlay as? FogOverlay else { return }
        let r = rect(for: mapRect)
        ctx.setFillColor(UIColor(red: 0.07, green: 0.05, blue: 0.18, alpha: 0.88).cgColor)
        ctx.fill(r)
        let mid = MKMapPoint(x: mapRect.midX, y: mapRect.midY)
        let w = CGFloat(60 * MKMapPointsPerMeterAtLatitude(mid.coordinate.latitude))
        let pad = mapRect.insetBy(dx: -Double(w) * 2, dy: -Double(w) * 2)
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for t in f.traces where t.count >= 2 {
            var on = false
            for i in 1..<t.count {
                let a = t[i - 1], b = t[i]
                let seg = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x) + 1, height: abs(a.y - b.y) + 1)
                if !seg.intersects(pad) { if on { ctx.strokePath(); on = false }; continue }
                if !on { ctx.move(to: point(for: a)); on = true }
                ctx.addLine(to: point(for: b))
            }
            if on { ctx.strokePath() }
        }
        ctx.setBlendMode(.normal)
    }
}
