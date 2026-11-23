import UIKit
import MapKit
import CoreLocation

/// Écran GPS natif sur la carte Apple Plans : position Apple (lissée, précise), vue 3D qui suit la route,
/// tracé du trajet coloré selon la conso, et toutes les infos de consommation par-dessus.
final class GPSViewController: UIViewController, MKMapViewDelegate {
    var range: Double?
    private let map = MKMapView()
    private var timer: Timer?
    private var trail: MKPolyline?
    private var trailColors: [UIColor] = []
    private var trailLocs: [CGFloat] = []
    private var trailCount = -1
    private var threeD = true
    private var follow = true
    private var freeAt = Date.distantPast

    private let speedL = UILabel(), gearL = UILabel(), accL = UILabel()
    private let consL = UILabel(), unitL = UILabel(), cutL = UILabel()
    private let barBg = UIView(), barFg = UIView()
    private var barW: NSLayoutConstraint!
    private var vals: [UILabel] = []
    private let line1 = UILabel(), line2 = UILabel()
    private let btn3D = UIButton(type: .system), btnRec = UIButton(type: .system), btnClose = UIButton(type: .system)

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark
        map.translatesAutoresizingMaskIntoConstraints = false
        map.delegate = self
        let cfg = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        cfg.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = cfg
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.isPitchEnabled = true
        view.addSubview(map)
        NSLayoutConstraint.activate([map.topAnchor.constraint(equalTo: view.topAnchor), map.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     map.leadingAnchor.constraint(equalTo: view.leadingAnchor), map.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(userMoved(_:)))
        pan.delegate = self
        map.addGestureRecognizer(pan)
        buildHUD()
        startFollow(animated: false)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    // MARK: - Caméra

    /// 2.68 : caméra pilotée par l'appli (et plus par la boussole du téléphone, qui fait « danser » la carte en voiture) :
    /// centre = position, orientation = direction de déplacement GPS lissée, distance par paliers de vitesse.
    private var camHeading: Double = 0
    private var camDist: Double = 500
    private var bandWant: Double = 500
    private var bandSince = Date()

    private func startFollow(animated: Bool) {
        follow = true
        map.setUserTrackingMode(.none, animated: false)
        if let l = Core.shared.rec.gps ?? map.userLocation.location, l.course >= 0 { camHeading = l.course }
        moveCamera(animated: animated, duration: 0.6)
    }

    @objc private func userMoved(_ g: UIPanGestureRecognizer) {
        if g.state == .began { follow = false; freeAt = Date() }
    }

    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        if mode != .none { mapView.setUserTrackingMode(.none, animated: false) }
    }

    private func band(_ kmh: Double) -> Double { kmh < 25 ? 450 : kmh < 55 ? 650 : kmh < 90 ? 950 : 1300 }

    private func moveCamera(animated: Bool, duration: Double) {
        guard let l = Core.shared.rec.gps ?? map.userLocation.location else { return }
        let kmh = max(0, l.speed) * 3.6
        // direction : seulement quand on roule vraiment, lissée (pas de demi-tours brusques de la carte)
        if kmh > 8, l.course >= 0, (l.courseAccuracy < 0 || l.courseAccuracy < 30) {
            var d = l.course - camHeading
            while d > 180 { d -= 360 }
            while d < -180 { d += 360 }
            camHeading = (camHeading + d * 0.45 + 360).truncatingRemainder(dividingBy: 360)
        }
        // distance : change seulement si le palier de vitesse est stable 4 s
        let b = band(kmh)
        if b != bandWant { bandWant = b; bandSince = Date() }
        if bandWant != camDist && Date().timeIntervalSince(bandSince) > 4 { camDist = bandWant }
        let cam = MKMapCamera(lookingAtCenter: l.coordinate, fromDistance: camDist, pitch: threeD ? 60 : 0, heading: camHeading)
        if animated {
            UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction]) { self.map.camera = cam }
        } else {
            map.camera = cam
        }
    }

    private func adjustCamera() {
        if !follow {
            if Date().timeIntervalSince(freeAt) > 12 { startFollow(animated: true) }
            return
        }
        moveCamera(animated: true, duration: 0.5)
    }

    // MARK: - Tracé coloré

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let pl = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
        let r = MKGradientPolylineRenderer(polyline: pl)
        r.setColors(trailColors, locations: trailLocs)
        r.lineWidth = 7
        r.lineCap = .round
        r.lineJoin = .round
        return r
    }

    private func updateTrail() {
        guard let R = Core.shared.rec.trip else {
            if let t = trail { map.removeOverlay(t); trail = nil; trailCount = -1 }
            return
        }
        let P = R.P
        if P.count == trailCount || P.count < 2 { return }
        trailCount = P.count
        var coords: [CLLocationCoordinate2D] = []
        var cols: [UIColor] = []
        var dist: [Double] = [0]
        for (i, p) in P.enumerated() {
            guard let la = p[0] as? Double, let lo = p[1] as? Double else { continue }
            let c = CLLocationCoordinate2D(latitude: la, longitude: lo)
            if i > 0, let last = coords.last {
                dist.append(dist.last! + CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: CLLocation(latitude: la, longitude: lo)))
            }
            coords.append(c)
            cols.append(GPSViewController.color(p[2] as? Double))
        }
        if coords.count < 2 { return }
        let tot = max(1, dist.last ?? 1)
        trailColors = cols
        trailLocs = dist.prefix(coords.count).map { CGFloat($0 / tot) }
        let pl = MKPolyline(coordinates: coords, count: coords.count)
        if let t = trail { map.removeOverlay(t) }
        trail = pl
        map.addOverlay(pl, level: .aboveRoads)
    }

    static func color(_ c: Double?) -> UIColor {
        guard let c = c else { return UIColor(red: 0.56, green: 0.53, blue: 0.79, alpha: 1) }
        let s = TripAttributes.ContentState(speed: 0, cons: c, lph: nil, avg: nil, km: 0, minutes: 0, cut: c == 0, gear: nil, cost: nil)
        let k = LMFmt.rgb(s)
        return UIColor(red: k.0, green: k.1, blue: k.2, alpha: 1)
    }

    // MARK: - Affichage

    private func card() -> UIView {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 18
        v.clipsToBounds = true
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.white.withAlphaComponent(0.1).cgColor
        view.addSubview(v)
        return v
    }

    private func lbl(_ l: UILabel, _ size: CGFloat, _ w: UIFont.Weight, _ col: UIColor = .white) {
        l.font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: w)
        if let d = l.font.fontDescriptor.withDesign(.rounded) { l.font = UIFont(descriptor: d, size: size) }
        l.textColor = col
        l.textAlignment = .center
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.6
    }

    private func vstack(_ v: [UIView], in c: UIView, spacing: CGFloat = 1) -> UIStackView {
        let s = UIStackView(arrangedSubviews: v)
        s.axis = .vertical
        s.alignment = .fill
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        let host = (c as? UIVisualEffectView)?.contentView ?? c
        host.addSubview(s)
        NSLayoutConstraint.activate([s.topAnchor.constraint(equalTo: host.topAnchor, constant: 8), s.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8),
                                     s.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12), s.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12)])
        return s
    }

    private func buildHUD() {
        let g = view.safeAreaLayoutGuide
        let grey = UIColor(white: 1, alpha: 0.55)
        // bouton fermer
        btnClose.setTitle("✕", for: .normal)
        btnClose.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        btnClose.tintColor = .white
        btnClose.backgroundColor = UIColor(red: 0.04, green: 0.03, blue: 0.12, alpha: 0.85)
        btnClose.layer.cornerRadius = 22
        btnClose.translatesAutoresizingMaskIntoConstraints = false
        btnClose.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(btnClose)
        // vitesse
        let left = card()
        lbl(speedL, 42, .heavy); let kmh = UILabel(); lbl(kmh, 12, .medium, grey); kmh.text = "km/h"
        lbl(gearL, 15, .bold, UIColor(red: 0, green: 0.9, blue: 1, alpha: 1)); lbl(accL, 10.5, .medium, grey)
        _ = vstack([speedL, kmh, gearL, accL], in: left)
        // conso
        let right = card()
        lbl(consL, 42, .heavy); lbl(unitL, 12, .medium, grey); lbl(cutL, 11.5, .semibold, UIColor(red: 0.37, green: 0.89, blue: 0.55, alpha: 1))
        barBg.backgroundColor = UIColor(white: 1, alpha: 0.12); barBg.layer.cornerRadius = 3; barBg.translatesAutoresizingMaskIntoConstraints = false
        barFg.layer.cornerRadius = 3; barFg.translatesAutoresizingMaskIntoConstraints = false
        barBg.addSubview(barFg)
        barW = barFg.widthAnchor.constraint(equalTo: barBg.widthAnchor, multiplier: 0.001)
        NSLayoutConstraint.activate([barBg.heightAnchor.constraint(equalToConstant: 6), barFg.leadingAnchor.constraint(equalTo: barBg.leadingAnchor),
                                     barFg.topAnchor.constraint(equalTo: barBg.topAnchor), barFg.bottomAnchor.constraint(equalTo: barBg.bottomAnchor), barW])
        _ = vstack([consL, unitL, barBg, cutL], in: right, spacing: 3)
        // boutons
        for (b, t) in [(btn3D, "3D"), (btnRec, "◎")] {
            b.setTitle(t, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold); b.tintColor = .white
            b.backgroundColor = UIColor(red: 0.04, green: 0.03, blue: 0.12, alpha: 0.85); b.layer.cornerRadius = 22
            b.layer.borderWidth = 1; b.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
            b.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(b)
        }
        btn3D.addTarget(self, action: #selector(toggle3D), for: .touchUpInside)
        btnRec.addTarget(self, action: #selector(recenter), for: .touchUpInside)
        // panneau du bas
        let pan = card()
        let caps = ["moy. trajet", "dernière min.", "5 dernières min.", "L/h maintenant", "carburant", "coût"]
        var cells: [UIView] = []
        for c in caps {
            let v = UILabel(); lbl(v, 21, .bold); v.text = "–"; vals.append(v)
            let cl = UILabel(); lbl(cl, 11, .regular, grey); cl.text = c
            let s = UIStackView(arrangedSubviews: [v, cl]); s.axis = .vertical; s.spacing = 0
            cells.append(s)
        }
        let r1 = UIStackView(arrangedSubviews: Array(cells[0..<3])), r2 = UIStackView(arrangedSubviews: Array(cells[3..<6]))
        for r in [r1, r2] { r.axis = .horizontal; r.distribution = .fillEqually; r.spacing = 4 }
        lbl(line1, 13, .semibold, UIColor(white: 1, alpha: 0.8)); lbl(line2, 12.5, .medium, UIColor(red: 0.61, green: 0.9, blue: 0.71, alpha: 1))
        line1.numberOfLines = 1; line2.numberOfLines = 1
        _ = vstack([r1, r2, line1, line2], in: pan, spacing: 6)
        NSLayoutConstraint.activate([
            btnClose.topAnchor.constraint(equalTo: g.topAnchor, constant: 6), btnClose.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            btnClose.widthAnchor.constraint(equalToConstant: 44), btnClose.heightAnchor.constraint(equalToConstant: 44),
            left.topAnchor.constraint(equalTo: g.topAnchor, constant: 6), left.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12), left.widthAnchor.constraint(equalToConstant: 104),
            right.topAnchor.constraint(equalTo: btnClose.bottomAnchor, constant: 8), right.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12), right.widthAnchor.constraint(equalToConstant: 132),
            btn3D.topAnchor.constraint(equalTo: right.bottomAnchor, constant: 10), btn3D.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            btn3D.widthAnchor.constraint(equalToConstant: 44), btn3D.heightAnchor.constraint(equalToConstant: 44),
            btnRec.topAnchor.constraint(equalTo: btn3D.bottomAnchor, constant: 8), btnRec.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            btnRec.widthAnchor.constraint(equalToConstant: 44), btnRec.heightAnchor.constraint(equalToConstant: 44),
            pan.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 8), pan.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -8),
            pan.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -6),
        ])
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func toggle3D() { threeD.toggle(); btn3D.setTitle(threeD ? "3D" : "2D", for: .normal); startFollow(animated: true) }
    @objc private func recenter() { startFollow(animated: true) }

    private static func n1(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
    private static func n2(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

    private func refresh() {
        let rec = Core.shared.rec, d = rec.d, R = rec.trip, k = rec.settings.k
        let price = UserDefaults.standard.double(forKey: "price")
        let g = rec.gps
        let gpsSpeed = g.map { max(0, $0.speed) * 3.6 }
        let speed = rec.obd.ready ? (d["speed"] ?? gpsSpeed ?? 0) : (gpsSpeed ?? 0)
        speedL.text = "\(Int(speed.rounded()))"
        if let st = rec.activityState(), let gr = st.gear { gearL.text = "\(gr)\(gr == 1 ? "re" : "e")" } else { gearL.text = " " }
        accL.text = g.map { "GPS ±\(max(1, Int($0.horizontalAccuracy.rounded()))) m" } ?? "GPS…"
        let cons: Double? = rec.cut ? 0 : d["cons"]
        if rec.cut { consL.text = "0"; unitL.text = "L/100" }
        else if let c = cons { consL.text = GPSViewController.n1(min(99, c)); unitL.text = "L/100" }
        else if let l = d["lph"] { consL.text = GPSViewController.n1(l); unitL.text = "L/h à l’arrêt" }
        else { consL.text = "–"; unitL.text = rec.obd.ready ? "L/100" : "OBD non connecté" }
        let col = GPSViewController.color(cons)
        consL.textColor = cons != nil ? col : .white
        cutL.text = rec.cut ? "coupure d’injection · 0 L" : " "
        barW.isActive = false
        barW = barFg.widthAnchor.constraint(equalTo: barBg.widthAnchor, multiplier: max(0.001, min(1, (cons ?? 0) / 20)))
        barW.isActive = true
        barFg.backgroundColor = col
        let avg: Double? = R != nil && R!.dist > 0.3 ? R!.fuel * k / R!.dist * 100 : nil
        let v1 = rec.winAvg(60), v5 = rec.winAvg(300)
        vals[0].text = avg.map { GPSViewController.n1($0) } ?? "–"
        vals[0].textColor = avg.map { GPSViewController.color($0) } ?? .white
        vals[1].text = v1.map { GPSViewController.n1($0) } ?? "–"
        vals[2].text = v5.map { GPSViewController.n1($0) } ?? "–"
        vals[3].text = d["lph"].map { GPSViewController.n1($0) } ?? "–"
        vals[4].text = R.map { GPSViewController.n2($0.fuel * k) + " L" } ?? "–"
        vals[5].text = R != nil && price > 0 ? GPSViewController.n2(R!.fuel * k * price) + " €" : "–"
        var parts: [String] = []
        if let R = R { parts.append(GPSViewController.n1(R.dist) + " km"); parts.append("\(Int(R.dur / 60)) min") }
        if let r = d["rpm"] { parts.append("\(Int((r / 10).rounded() * 10)) tr/min") }
        if let c = d["coolant"] { parts.append("\(Int(c.rounded()))° eau") }
        if let rg = range { parts.append("\(Int((rg / 5).rounded() * 5)) km d’autonomie") }
        line1.text = parts.isEmpty ? "En attente du trajet…" : parts.joined(separator: "  ·  ")
        line2.text = R == nil ? (rec.obd.ready ? "Le trajet démarre dès que tu roules." : "Connecte l’OBD pour avoir la conso.") : (rec.cut ? "Coupure d’injection : tu roules sans carburant" : " ")
        updateTrail()
        adjustCamera()
    }
}

extension GPSViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith o: UIGestureRecognizer) -> Bool { true }
}
