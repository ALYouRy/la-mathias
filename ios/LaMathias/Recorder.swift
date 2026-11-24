import Foundation
import CoreLocation
import UIKit
import UserNotifications

/// Un trajet en cours : mêmes champs que l'enregistreur de l'appli web (recNew) et de l'autoradio.
final class Trip {
    var t0: Double = Date().timeIntervalSince1970 * 1000
    var dur = 0.0, mov = 0.0, idle = 0.0, stop = 0.0, off = 0.0, dist = 0.0, fuel = 0.0, vmax = 0.0
    var rpmMax = 0.0, rpmMin = 99999.0, rpmSum = 0.0, rpmN = 0.0, over = 0
    var tMax = 0.0, tSum = 0.0, tN = 0.0, vMin = 99.0, vSum = 0.0, vN = 0.0, load = 0.0, lN = 0.0
    var brakes = 0, hard = 0, accel = 0, stops = 0
    var cutKm = 0.0   // km roulés injection coupée (0 L/100)
    var pv: Double? = nil
    var bd = 0.0, bt = false, hf = false, af = false, ov = false
    var P: [[Any]] = []
    var lastP = 0.0

    func dict() -> [String: Any] {
        ["t0": t0, "src": "obd", "native": true, "dur": dur, "mov": mov, "idle": idle, "stop": stop, "off": off, "dist": dist, "fuel": fuel, "vmax": vmax,
         "rpmMax": rpmMax, "rpmMin": rpmMin, "rpmSum": rpmSum, "rpmN": rpmN, "over": over, "tMax": tMax, "tSum": tSum, "tN": tN,
         "vMin": vMin, "vSum": vSum, "vN": vN, "load": load, "lN": lN, "brakes": brakes, "hard": hard, "accel": accel, "stops": stops, "cutKm": cutKm, "P": P, "lastP": lastP]
    }

    static func from(_ d: [String: Any]) -> Trip {
        let t = Trip()
        func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        t.t0 = n("t0"); t.dur = n("dur"); t.mov = n("mov"); t.idle = n("idle"); t.stop = n("stop"); t.dist = n("dist"); t.fuel = n("fuel"); t.vmax = n("vmax")
        t.rpmMax = n("rpmMax"); t.rpmMin = d["rpmMin"] == nil ? 99999 : n("rpmMin"); t.rpmSum = n("rpmSum"); t.rpmN = n("rpmN"); t.over = Int(n("over"))
        t.tMax = n("tMax"); t.tSum = n("tSum"); t.tN = n("tN"); t.vMin = d["vMin"] == nil ? 99 : n("vMin"); t.vSum = n("vSum"); t.vN = n("vN"); t.load = n("load"); t.lN = n("lN")
        t.brakes = Int(n("brakes")); t.hard = Int(n("hard")); t.accel = Int(n("accel")); t.stops = Int(n("stops")); t.cutKm = n("cutKm")
        t.P = (d["P"] as? [[Any]]) ?? []; t.lastP = n("lastP")
        return t
    }
}

/// Lit la voiture en boucle, calcule la conso (comme l'autoradio) et enregistre les trajets avec le GPS, même écran verrouillé.
final class Recorder: NSObject, CLLocationManagerDelegate {
    let obd: OBD
    let loc = CLLocationManager()
    var d: [String: Double] = [:]
    var cut = false
    var dataT = 0.0
    var trip: Trip?
    var gps: CLLocation?
    private var loopOn = false
    private var n = 0
    private var mafBad = 0
    private var timer: Timer?
    private var last = Date()
    private var saveAcc = 0.0
    private var cutT: Double?, cutM: Double?, cutS = 0.0
    private var locMode = "off"

    init(obd: OBD) { self.obd = obd; super.init() }

    struct Settings { var disp = 1.2, k = 1.0, redline = 5000.0, endMin = 5.0 }
    var settings: Settings {
        let u = UserDefaults.standard
        var s = Settings()
        if u.double(forKey: "disp") > 0 { s.disp = u.double(forKey: "disp") }
        if u.double(forKey: "k") > 0 { s.k = u.double(forKey: "k") }
        if u.double(forKey: "redline") > 0 { s.redline = u.double(forKey: "redline") }
        if u.double(forKey: "endMin") > 0 { s.endMin = u.double(forKey: "endMin") }
        return s
    }
    func setSettings(_ m: [String: Any]) {
        for k in ["disp", "k", "redline", "endMin", "price", "fuelL", "rangeC"] { if let v = (m[k] as? NSNumber)?.doubleValue, v > 0 { UserDefaults.standard.set(v, forKey: k) } }
    }

    func setup() {
        loc.delegate = self
        loc.activityType = .automotiveNavigation
        loc.pausesLocationUpdatesAutomatically = false
        loc.showsBackgroundLocationIndicator = true
        cutT = UserDefaults.standard.object(forKey: "cutT") as? Double
        cutM = UserDefaults.standard.object(forKey: "cutM") as? Double
        obd.onReady = { [weak self] in self?.onReady() }
        obd.onLost = { [weak self] in self?.onLost() }
        obd.onState = { [weak self] in self?.pushLive() }
        restoreActive()
        NotificationCenter.default.addObserver(self, selector: #selector(appActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: - Autorisations

    func askPermissions() {
        let st = loc.authorizationStatus
        if st == .notDetermined { loc.requestWhenInUseAuthorization() }
        else if st == .authorizedWhenInUse { loc.requestAlwaysAuthorization() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse { m.requestAlwaysAuthorization() }
        pushLive()
    }

    var locAuth: String {
        switch loc.authorizationStatus {
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "inuse"
        case .denied, .restricted: return "denied"
        default: return "none"
        }
    }

    /// GPS précis pendant un trajet, très économe quand la voiture est connectée mais à l'arrêt, coupé sinon.
    private func setLoc(_ mode: String) {
        if mode == locMode { return }
        locMode = mode
        if mode == "off" { loc.stopUpdatingLocation(); loc.allowsBackgroundLocationUpdates = false; return }
        let st = loc.authorizationStatus
        guard st == .authorizedAlways || st == .authorizedWhenInUse else { return }
        loc.allowsBackgroundLocationUpdates = true
        if mode == "best" { loc.desiredAccuracy = kCLLocationAccuracyBestForNavigation; loc.distanceFilter = kCLDistanceFilterNone }
        else { loc.desiredAccuracy = kCLLocationAccuracyThreeKilometers; loc.distanceFilter = 3000 }
        loc.startUpdatingLocation()
    }

    private var lastPush = Date.distantPast
    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        // on ignore les mesures très imprécises si on en a une bonne récente
        if let g = gps, l.horizontalAccuracy > 50, g.horizontalAccuracy <= 20, l.timestamp.timeIntervalSince(g.timestamp) < 5 { return }
        gps = l
        // appli ouverte : position envoyée tout de suite à l'écran GPS (jusqu'à 5 fois par seconde)
        if UIApplication.shared.applicationState == .active, Date().timeIntervalSince(lastPush) > 0.2 {
            lastPush = Date()
            pushLive()
        }
    }

    /// Appli à l'écran : GPS au maximum de précision, même sans trajet. En arrière-plan : seulement ce qu'il faut.
    @objc private func appActive() { foreground = true; applyLoc() }
    @objc private func appBackground() { foreground = false; applyLoc() }
    private var foreground = false
    private func applyLoc() {
        if foreground || trip != nil { setLoc("best") } else if obd.ready { setLoc("low") } else { setLoc("off") }
    }

    // MARK: - Lecture en boucle

    private func onReady() {
        mafBad = 0
        applyLoc()
        // tension batterie juste à la connexion (moteur arrêté = tension de repos)
        read("rpm") { _ in
            self.obd.send("ATRV") { r in
                if let v = Recorder.volt(r) { self.d["volt"] = v; self.d["voltFirst"] = v; self.d["voltFirstRun"] = (self.d["rpm"] ?? 0) > 400 ? 1 : 0 }
                self.loop()
            }
        }
        pushLive()
    }

    private func onLost() {
        loopOn = false
        if let t = trip, (d["speed"] ?? 0) < 5 { _ = t; endTrip() }
        d = [:]
        dataT = 0
        applyLoc()
        pushLive()
    }

    static func volt(_ r: String?) -> Double? {
        guard let r = r else { return nil }
        let s = r.replacingOccurrences(of: ",", with: ".").filter { "0123456789.".contains($0) }
        if let v = Double(s), v > 6, v < 20 { return v }
        return nil
    }

    private let pids: [String: (String, ([Int]) -> Double)] = [
        "rpm": ("010C", { Double($0[0] * 256 + ($0.count > 1 ? $0[1] : 0)) / 4 }),
        "speed": ("010D", { Double($0[0]) }),
        "coolant": ("0105", { Double($0[0]) - 40 }),
        "iat": ("010F", { Double($0[0]) - 40 }),
        "load": ("0104", { Double($0[0]) * 100 / 255 }),
        "map": ("010B", { Double($0[0]) }),
        "maf": ("0110", { Double($0[0] * 256 + ($0.count > 1 ? $0[1] : 0)) / 100 }),
        "thr": ("0111", { Double($0[0]) * 100 / 255 }),
        "timing": ("010E", { Double($0[0]) / 2 - 64 }),
        "stft": ("0106", { Double($0[0]) * 100 / 128 - 100 }),
        "ltft": ("0107", { Double($0[0]) * 100 / 128 - 100 }),
        "fuel": ("012F", { Double($0[0]) * 100 / 255 }),
        "fr": ("015E", { Double($0[0] * 256 + ($0.count > 1 ? $0[1] : 0)) / 20 }),
        "eq": ("0144", { Double($0[0] * 256 + ($0.count > 1 ? $0[1] : 0)) * 2 / 65536 }),
    ]

    private func sup(_ k: String) -> Bool {
        guard let p = pids[k], let v = Int(p.0.suffix(2), radix: 16) else { return false }
        return obd.sup.contains(v)
    }

    /// CAN : « 010C1 » = « une seule réponse attendue », l'adaptateur répond sans attendre son délai (bien plus rapide)
    private var oneResp = true, oneFail = 0
    private func read(_ k: String, _ done: @escaping (Bool) -> Void) {
        guard let p = pids[k] else { done(false); return }
        let fast = obd.can && oneResp
        obd.send(p.0 + (fast ? "1" : "")) { r in
            let hdr = "4" + String(p.0.dropFirst())
            if fast && (k == "rpm" || k == "speed") {
                if OBD.bytes(r, hdr) == nil { self.oneFail += 1; if self.oneFail >= 3 { self.oneResp = false } } else { self.oneFail = 0 }
            }
            if let b = OBD.bytes(r, hdr) {
                self.d[k] = p.1(b)
                if k == "maf" { self.mafBad = 0 }
                done(true)
            } else {
                if k == "maf" { self.mafBad += 1; self.d["maf"] = nil }
                if r != nil && (k == "rpm") { self.d["rpm"] = nil }
                done(false)
            }
        }
    }

    private func loop() {
        if loopOn { return }
        loopOn = true
        n = 0
        next()
    }

    private func next() {
        guard loopOn, obd.ready else { loopOn = false; return }
        // 2.67 : d'abord l'essentiel (régime, vitesse, air, papillon) → conso recalculée et affichée aussitôt
        var L = ["rpm", "speed"]
        if sup("fr") { L.append("fr") }
        else if sup("maf") && mafBad < 3 { L.append("maf"); if mafBad > 0 { L.append("map") } } else { L.append("map") }
        if sup("thr") { L.append("thr") }
        let core = L.count
        if !(sup("maf") && mafBad < 3) && n % 4 == 0 { L.append("iat") }
        if sup("eq") && n % 3 == 0 { L.append("eq") }
        if n % 6 == 1 && sup("timing") { L.append("timing") }
        if n % 5 == 0 { L.append("coolant"); if sup("stft") { L.append("stft") }; if sup("ltft") { L.append("ltft") } }
        if n % 10 == 0 { L.append("load") }
        if n % 40 == 0 && sup("fuel") { L.append("fuel") }
        var i = 0
        let finish = {
            self.n += 1
            self.derive()
            // voiture coupée (pas de régime) : on interroge moins souvent
            let idle = self.d["rpm"] == nil && self.trip == nil
            DispatchQueue.main.asyncAfter(deadline: .now() + (idle ? 3 : 0.01)) { self.next() }
        }
        func extra() {
            var ex: [String] = []
            if n % 3 == 0 { ex.append("0103") }
            if n % 30 == 0 { ex.append("ATRV") }
            var j = 0
            func one() {
                if j >= ex.count { finish(); return }
                let c = ex[j]; j += 1
                obd.send(c) { r in
                    if c == "0103", let b = OBD.bytes(r, "4103") { self.d["fss"] = Double(b[0]) }
                    if c == "ATRV", let v = Recorder.volt(r) { self.d["volt"] = v }
                    one()
                }
            }
            one()
        }
        func step() {
            if i >= L.count { extra(); return }
            let k = L[i]; i += 1
            read(k) { ok in
                if ok && (k == "rpm" || k == "speed") { self.dataT = Date().timeIntervalSince1970 }
                if i == core { self.derive(); self.pushFast(); self.liveTick() }
                step()
            }
        }
        step()
    }

    /// Conso instantanée (2.58) : débit d'air (MAF, ou pression × régime avec rendement selon le régime), richesse
    /// (boucle fermée = mélange idéal + trims, pleine charge / moteur froid = enrichi), 015E / 0144 si la voiture les donne.
    /// Coupure d'injection seulement si tout concorde : rapport engagé et stable, pied levé, forte dépression, régime qui ne monte pas.
    static let veK: [(Double, Double)] = [(600, 0.62), (1000, 0.68), (1500, 0.74), (2000, 0.78), (2500, 0.82), (3000, 0.85), (3500, 0.88), (4000, 0.9), (5000, 0.88), (6000, 0.83), (7000, 0.78)]
    static func ve(_ r: Double) -> Double {
        if r <= veK[0].0 { return veK[0].1 }
        for i in 1..<veK.count where r <= veK[i].0 {
            let a = veK[i - 1], b = veK[i]
            return a.1 + (b.1 - a.1) * (r - a.0) / (b.0 - a.0)
        }
        return veK[veK.count - 1].1
    }
    static let gearK: [Double] = [7.5, 13.5, 20, 27, 34]
    private var pR: Double? = nil, pRatio: Double? = nil, cutN = 0, pLph: Double? = nil
    var src = ""

    private func derive() {
        let s = settings
        let r = d["rpm"], v = d["speed"] ?? 0
        if let r = r, r > 550, r < 1150, v < 2 {
            if let thr = d["thr"] {
                if let t = cutT { cutT = min(t + 0.02, t * 0.97 + thr * 0.03); if thr < cutT! { cutT = thr } } else { cutT = thr }
            }
            if let m = d["map"], (d["coolant"] ?? 99) > 60 { cutM = cutM == nil ? m : cutM! * 0.97 + m * 0.03 }
            let now = Date().timeIntervalSince1970
            if now - cutS > 30 { cutS = now; UserDefaults.standard.set(cutT, forKey: "cutT"); UserDefaults.standard.set(cutM, forKey: "cutM") }
        }
        var lph: Double? = nil
        let fss = d["fss"]
        if let fr = d["fr"], fr >= 0, fr < 60 { lph = fr; src = "mesurée" } else {
            var air = d["maf"]
            src = "débit d’air"
            if air == nil, let m = d["map"], let r = r {
                air = r / 120 * s.disp * Recorder.ve(r) * (m * 1000) / (287.05 * ((d["iat"] ?? 25) + 273.15))
                src = "pression d’admission"
            }
            if let a = air {
                var phi = 1.0
                let cl = fss == 2 || fss == nil
                if let eq = d["eq"], eq > 0.6, eq < 1.6 { phi = eq }
                else if !cl {
                    let hi = (d["map"] ?? 0) >= 85 || (d["load"] ?? 0) >= 80 || (d["thr"] != nil && cutT != nil && d["thr"]! > cutT! + 55)
                    if hi { phi = 1.15 } else if let c = d["coolant"], c < 65 { phi = 1 + min(0.3, (65 - c) * 0.008) }
                }
                var trim = 1 + (d["ltft"] ?? 0) / 100 + (cl ? (d["stft"] ?? 0) / 100 : 0)
                trim = max(0.75, min(1.25, trim))
                lph = a / 14.7 * phi * trim * 3600 / 745
            }
        }
        guard var l = lph else { d["lph"] = nil; d["lphRaw"] = nil; d["cons"] = nil; cut = false; src = ""; return }
        var ratio: Double? = nil
        var gear = false
        if let r = r, v >= 4, r >= 650 {
            let k = v / (r / 1000)
            ratio = k
            gear = Recorder.gearK.contains { abs(log(k / $0)) < 0.22 }
        }
        let stable = ratio != nil && pRatio != nil && abs(ratio! / pRatio! - 1) < 0.08
        let notRising = pR == nil || r == nil || r! - pR! <= 60
        let foot: Bool = d["thr"] == nil ? true : (cutT != nil ? d["thr"]! <= cutT! + 1.5 : d["thr"]! < 16)
        // papillon connu et fermé : une dépression modérée suffit ; sinon on exige une forte dépression
        let thrKnown = d["thr"] != nil && cutT != nil
        let vac: Bool = d["map"] != nil ? (thrKnown ? d["map"]! < (cutM.map { $0 * 0.9 } ?? 30) : (cutM != nil ? d["map"]! < cutM! * 0.8 : d["map"]! < 26)) : ((d["load"] ?? 100) < 15)
        // coupure d'injection : pied levé + forte dépression + régime ≥ 1200 qui ne monte pas (rapport engagé ou non)
        _ = gear; _ = stable
        let cand = src != "mesurée" && (r ?? 0) >= 1200 && notRising && foot && vac
        cutN = cand ? cutN + 1 : 0
        pRatio = ratio
        pR = r
        cut = cutN >= 2
        if cut { l = 0 }
        pLph = l
        d["lphRaw"] = l
        d["lph"] = l * max(0.6, min(1.6, s.k))
        d["cons"] = v > 8 ? d["lph"]! / v * 100 : nil
    }

    // MARK: - Enregistrement (chaque seconde)

    private func tick() {
        let now = Date()
        let dt = min(5, now.timeIntervalSince(last))
        last = now
        recTick(dt)
        liveTick()
        hist.append((d["lph"], d["speed"] ?? 0))
        if hist.count > 600 { hist.removeFirst(hist.count - 600) }
        if UIApplication.shared.applicationState == .active { pushLive() }
    }

    private var fastT = Date.distantPast
    /// envoi immédiat à l'écran (jusqu'à ~7 fois par seconde) dès qu'une nouvelle conso est calculée
    func pushFast() {
        guard UIApplication.shared.applicationState == .active, Date().timeIntervalSince(fastT) > 0.14 else { return }
        fastT = Date()
        pushLive()
    }

    /// historique seconde par seconde (L/h, km/h) pour les moyennes « dernière minute » / « 5 min »
    var hist: [(Double?, Double)] = []
    func winAvg(_ n: Int) -> Double? {
        let a = hist.suffix(n)
        var l = 0.0, km = 0.0
        for (h, v) in a { if let h = h { l += h / 3600 }; km += v / 3600 }
        return km > 0.02 && l > 0 ? l / km * 100 : nil
    }

    // MARK: - Dynamic Island

    func activityState() -> TripAttributes.ContentState? {
        guard let R = trip else { return nil }
        let k = settings.k
        var gear: Int? = nil
        if let r = d["rpm"], let v = d["speed"], v >= 4, r >= 650 {
            let ratio = v / (r / 1000)
            var best = 0, bd = 1e9
            for (i, g) in Recorder.gearK.enumerated() { let x = abs(log(ratio / g)); if x < bd { bd = x; best = i + 1 } }
            if bd < 0.22 { gear = best }
        }
        let price = UserDefaults.standard.double(forKey: "price")
        return TripAttributes.ContentState(
            speed: Int((d["speed"] ?? 0).rounded()),
            cons: cut ? 0 : d["cons"], lph: d["lph"],
            avg: R.dist > 0.3 ? R.fuel * k / R.dist * 100 : nil,
            km: R.dist, minutes: Int(R.dur / 60), cut: cut, gear: gear,
            cost: price > 0 ? R.fuel * k * price : nil,
            rpm: d["rpm"].map { Int($0.rounded()) },
            range: rangeLeft(R).map { Int($0.rounded()) },
            left: fuelLeft(R),
            cutKm: R.cutKm > 0.01 ? R.cutKm : nil,
            vmax: R.vmax > 0 ? Int(R.vmax.rounded()) : nil)
    }

    /// litres restants = niveau envoyé par l'appli au début, moins ce que ce trajet a consommé
    private func fuelLeft(_ R: Trip) -> Double? {
        let f = UserDefaults.standard.double(forKey: "fuelL")
        guard f > 0 else { return nil }
        return max(0, f - R.fuel * settings.k)
    }
    private func rangeLeft(_ R: Trip) -> Double? {
        let c = UserDefaults.standard.double(forKey: "rangeC")
        guard let l = fuelLeft(R), c > 2 else { return nil }
        return l / c * 100
    }

    private func liveTick() {
        guard let st = activityState() else { return }
        let la = LiveAct.shared
        if !la.running, UIApplication.shared.applicationState == .active, let R = trip {
            la.start(st, since: Date(timeIntervalSince1970: R.t0 / 1000))
        }
        la.update(st)
    }

    private func notifyStart() {
        if UIApplication.shared.applicationState == .active || LiveAct.shared.running || !LiveAct.shared.enabled { return }
        let c = UNMutableNotificationContent()
        c.title = "Trajet démarré"
        c.body = "Touche ici pour afficher la vitesse et la conso dans la Dynamic Island."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trip-start", content: c, trigger: nil))
    }

    private func recTick(_ dt: Double) {
        let s = settings
        let speed = d["speed"] ?? 0
        let rpm = d["rpm"]
        let fresh = dataT > 0 && Date().timeIntervalSince1970 - dataT < 5
        let run = obd.ready && fresh && (rpm ?? 0) > 200
        guard let R = trip else {
            if run && speed >= 5 {
                trip = Trip()
                setLoc("best")
                pushLive()
                notifyStart()
            }
            return
        }
        if !run {
            R.off += dt
            if R.off >= 25 { endTrip() }
            return
        }
        R.off = 0
        R.dur += dt
        let moving = speed >= 1
        if moving { R.mov += dt; R.stop = 0 } else { R.idle += dt; R.stop += dt }
        if let pv = R.pv, pv >= 1, !moving { R.stops += 1 }
        R.dist += speed * dt / 3600
        if let l = d["lphRaw"] { R.fuel += l * dt / 3600 }
        if cut && moving { R.cutKm += speed * dt / 3600 }
        if speed > R.vmax { R.vmax = speed }
        if let rp = rpm {
            R.rpmSum += rp; R.rpmN += 1
            if rp > R.rpmMax { R.rpmMax = rp }
            if rp < R.rpmMin { R.rpmMin = rp }
            if rp >= s.redline { if !R.ov { R.over += 1; R.ov = true } } else { R.ov = false }
        }
        if let c = d["coolant"] { R.tSum += c; R.tN += 1; if c > R.tMax { R.tMax = c } }
        if let v = d["volt"] { R.vSum += v; R.vN += 1; if v < R.vMin { R.vMin = v } }
        if let l = d["load"] { R.load += l; R.lN += 1 }
        if let pv = R.pv {
            let dv = (pv - speed) / dt, ac = (speed - pv) / dt
            if dv >= 6 {
                R.bd += dt
                if !R.bt && R.bd >= 0.8 { R.bt = true; R.brakes += 1 }
                if dv >= 14 && !R.hf { R.hf = true; R.hard += 1 }
            } else { R.bd = 0; R.bt = false; R.hf = false }
            if ac >= 12 { if !R.af { R.af = true; R.accel += 1 } } else { R.af = false }
        }
        R.pv = speed
        // point du tracé : au plus 1 par seconde (12 m mini), avec conso, vitesse et secondes depuis le point précédent
        // 2.60 : un point par seconde dès 4 m parcourus si le GPS est précis (≤ 25 m), sauts impossibles rejetés
        if let g = gps, g.horizontalAccuracy >= 0, g.horizontalAccuracy <= 60, Date().timeIntervalSince(g.timestamp) < 8 {
            let nowMs = Date().timeIntervalSince1970 * 1000
            var add = R.P.isEmpty
            if let lp = R.P.last, let la = lp[0] as? Double, let lo = lp[1] as? Double {
                let dd = CLLocation(latitude: la, longitude: lo).distance(from: g)
                let dt = max(0.5, (nowMs - R.lastP) / 1000)
                let minD = g.horizontalAccuracy <= 25 ? 4.0 : 12.0
                add = ((dd >= minD && nowMs - R.lastP >= 1000) || nowMs - R.lastP >= 15000) && dd / dt < 75
            }
            if add {
                let c: Any = d["cons"].map { min(99, $0) } ?? NSNull()
                R.P.append([g.coordinate.latitude, g.coordinate.longitude, c, Int(speed.rounded()), R.P.isEmpty ? 0 : Int(((nowMs - R.lastP) / 1000).rounded())])
                R.lastP = nowMs
            }
        }
        saveAcc += dt
        if saveAcc >= 15 { saveAcc = 0; saveActive() }
        if R.stop >= s.endMin * 60 { endTrip() }
    }

    func endTrip() {
        guard let R = trip else { return }
        LiveAct.shared.end(activityState())
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["trip-start"])
        trip = nil
        UserDefaults.standard.removeObject(forKey: "activeTrip")
        applyLoc()
        if R.dist >= 0.2 && R.dur >= 30 {
            Store.add(R.dict())
            notifyTrip(R)
            Core.shared.js("window.LMN&&LMN.tripsReady()")
        }
        pushLive()
    }

    private func notifyTrip(_ R: Trip) {
        let c = UNMutableNotificationContent()
        c.title = "Trajet enregistré"
        let km = String(format: "%.1f", R.dist).replacingOccurrences(of: ".", with: ",")
        let cons = R.dist > 0.5 ? " · " + String(format: "%.1f", R.fuel * settings.k / R.dist * 100).replacingOccurrences(of: ".", with: ",") + " L/100" : ""
        c.body = km + " km en " + String(Int(R.dur / 60)) + " min" + cons + ". Ouvre La Mathias pour le voir."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "trip-\(Int(R.t0))", content: c, trigger: nil))
    }

    private func saveActive() {
        guard let R = trip else { return }
        var dct = R.dict()
        dct["saved"] = Date().timeIntervalSince1970
        if let data = try? JSONSerialization.data(withJSONObject: dct) { UserDefaults.standard.set(data, forKey: "activeTrip") }
    }

    /// Si l'appli a été fermée en plein trajet : on le reprend s'il est récent, sinon on l'enregistre tel quel.
    private func restoreActive() {
        guard let data = UserDefaults.standard.data(forKey: "activeTrip"), let dct = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        let t = Trip.from(dct)
        let saved = (dct["saved"] as? NSNumber)?.doubleValue ?? 0
        if Date().timeIntervalSince1970 - saved < 300 { trip = t; return }
        UserDefaults.standard.removeObject(forKey: "activeTrip")
        if t.dist >= 0.2 && t.dur >= 30 { Store.add(t.dict()) }
    }

    // MARK: - Vers la page

    func liveDict() -> [String: Any] {
        var dd: [String: Any] = [:]
        for (k, v) in d where v.isFinite { dd[k] = v }
        dd["cut"] = cut
        dd["src"] = src
        var o: [String: Any] = ["st": obd.state, "err": obd.err, "name": obd.savedName, "known": obd.savedId != nil, "can": obd.can, "d": dd, "loc": locAuth, "pending": Store.count(), "isl": LiveAct.shared.available]
        if let R = trip { o["rec"] = ["t0": R.t0, "dist": R.dist, "dur": R.dur, "fuel": R.fuel, "cutKm": R.cutKm, "P": R.P.count] }
        if let g = gps { o["gps"] = ["la": g.coordinate.latitude, "lo": g.coordinate.longitude, "acc": g.horizontalAccuracy, "crs": g.course, "sp": g.speed >= 0 ? g.speed * 3.6 : -1, "t": g.timestamp.timeIntervalSince1970 * 1000] }
        return o
    }

    func pushLive() {
        guard UIApplication.shared.applicationState != .background else { return }
        Core.shared.js("window.LMN&&LMN.live(" + Core.json(liveDict()) + ")")
    }
}

/// Trajets terminés en attente d'être repris par la page (fichier dans l'appli).
enum Store {
    static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("trajets.json") }
    static func all() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url), let a = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return a
    }
    static func write(_ a: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: a) { try? data.write(to: url, options: .atomic) }
    }
    static func add(_ t: [String: Any]) { var a = all(); a.append(t); write(a) }
    static func ack(_ ids: [Double]) { write(all().filter { t in !ids.contains { abs($0 - ((t["t0"] as? NSNumber)?.doubleValue ?? -1)) < 1 } }) }
    static func count() -> Int { all().count }
}
