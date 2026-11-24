import Foundation
import MapKit

/// 2.87 : itinéraire Apple Plans entre deux points, pour recoller un trajet GPS sur les vraies routes.
/// Le web envoie des paires de points (ancres prises sur le trajet) ; on renvoie les tracés routiers proposés par Plans
/// (avec les variantes), et c'est le web qui garde celui qui colle le mieux au passage réel.
enum PlansRoute {
    static func run(id: String, a: [Double], b: [Double], done: @escaping (String) -> Void) {
        guard a.count >= 2, b.count >= 2 else { done("{\"id\":\"\(id)\",\"err\":\"pts\"}"); return }
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: a[0], longitude: a[1])))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: b[0], longitude: b[1])))
        req.transportType = .automobile
        req.requestsAlternateRoutes = true
        MKDirections(request: req).calculate { resp, err in
            if let e = err as NSError? {
                let thr = e.domain == MKErrorDomain && e.code == Int(MKError.loadingThrottled.rawValue)
                done("{\"id\":\"\(id)\",\"err\":\"\(thr ? "throttled" : "fail")\"}")
                return
            }
            var routes: [[[Double]]] = []
            for r in resp?.routes ?? [] {
                let n = r.polyline.pointCount
                var cs = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: n)
                r.polyline.getCoordinates(&cs, range: NSRange(location: 0, length: n))
                routes.append(cs.map { [($0.latitude * 1e6).rounded() / 1e6, ($0.longitude * 1e6).rounded() / 1e6] })
            }
            let o: [String: Any] = ["id": id, "routes": routes]
            done(Core.json(o))
        }
    }
}
