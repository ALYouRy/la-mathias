import UIKit
import MapKit

/// 2.87 : revue d'un trajet sur la carte Apple Plans (tracé coloré selon la conso, départ et arrivée).
final class TripMapViewController: UIViewController, MKMapViewDelegate {
    var pts: [[Double]] = []          // [lat, lon, conso L/100 ou -1]
    var titleText = ""
    var subText = ""
    private let map = MKMapView()
    private var colors: [UIColor] = []
    private var locs: [CGFloat] = []

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
        map.showsCompass = true
        view.addSubview(map)
        NSLayoutConstraint.activate([map.topAnchor.constraint(equalTo: view.topAnchor), map.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     map.leadingAnchor.constraint(equalTo: view.leadingAnchor), map.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        buildHeader()
        drawTrack()
    }

    private func buildHeader() {
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18
        card.clipsToBounds = true
        view.addSubview(card)
        let t = UILabel(), s = UILabel()
        t.text = titleText; t.font = .systemFont(ofSize: 18, weight: .heavy); t.textColor = .white
        s.text = subText; s.font = .systemFont(ofSize: 13, weight: .semibold); s.textColor = UIColor(white: 1, alpha: 0.65)
        let st = UIStackView(arrangedSubviews: [t, s]); st.axis = .vertical; st.spacing = 2
        st.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(st)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)), for: .normal)
        close.tintColor = .white
        close.backgroundColor = UIColor(white: 1, alpha: 0.14)
        close.layer.cornerRadius = 18
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTap), for: .touchUpInside)
        card.contentView.addSubview(close)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            st.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 16),
            st.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 12),
            st.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -12),
            st.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -10),
            close.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: card.contentView.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 36), close.heightAnchor.constraint(equalToConstant: 36)])
    }

    @objc private func closeTap() { dismiss(animated: true) }

    private func drawTrack() {
        var coords: [CLLocationCoordinate2D] = []
        var dist: [Double] = []
        var tot = 0.0
        for p in pts where p.count >= 2 {
            let c = CLLocationCoordinate2D(latitude: p[0], longitude: p[1])
            if let l = coords.last { tot += CLLocation(latitude: l.latitude, longitude: l.longitude).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) }
            coords.append(c); dist.append(tot)
            colors.append(GPSViewController.color(p.count > 2 && p[2] >= 0 ? p[2] : nil))
        }
        guard coords.count >= 2 else { return }
        locs = dist.map { CGFloat($0 / max(1, tot)) }
        let pl = MKPolyline(coordinates: coords, count: coords.count)
        map.addOverlay(pl, level: .aboveRoads)
        let a = MKPointAnnotation(); a.coordinate = coords.first!; a.title = "Départ"
        let b = MKPointAnnotation(); b.coordinate = coords.last!; b.title = "Arrivée"
        map.addAnnotations([a, b])
        map.setVisibleMapRect(pl.boundingMapRect, edgePadding: UIEdgeInsets(top: 130, left: 40, bottom: 60, right: 40), animated: false)
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
        let v = MKMarkerAnnotationView(annotation: a, reuseIdentifier: "p")
        v.markerTintColor = a.title == "Départ" ? UIColor(red: 0.2, green: 0.82, blue: 0.48, alpha: 1) : UIColor(red: 0.94, green: 0.33, blue: 0.31, alpha: 1)
        v.glyphImage = UIImage(systemName: a.title == "Départ" ? "flag.fill" : "flag.checkered")
        return v
    }
}
