import Foundation
import CoreBluetooth

/// Liaison Bluetooth LE avec un adaptateur ELM327 (vLinker, Vgate iCar…), en arrière-plan.
/// Même dialogue que l'autoradio : ATZ, ATE0, ATL0, ATS0, ATH0, ATAT1, ATSP0 puis 0100.
final class OBD: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let restoreId = "fr.lamathias.obd"

    private(set) var central: CBCentralManager!
    private(set) var peripheral: CBPeripheral?
    private var notifyChar: CBCharacteristic?
    private var writeChar: CBCharacteristic?
    private var pendingServices = 0

    /// off, scan, wait (attend le boîtier), conn, init, ok, lost
    var state = "off" { didSet { if oldValue != state { onState?() } } }
    var err = ""
    var can = false
    var sup = Set<Int>()
    var ready: Bool { state == "ok" }

    var onFound: (([[String: Any]], Bool) -> Void)?
    var onReady: (() -> Void)?
    var onLost: (() -> Void)?
    var onState: (() -> Void)?

    private var found: [UUID: (CBPeripheral, Int)] = [:]
    private var buf = ""
    private var queue: [(cmd: String, timeout: Double, cb: (String?) -> Void)] = []
    private var current: ((String?) -> Void)?
    private var timeoutItem: DispatchWorkItem?
    private var initToken = 0

    private let known: [CBUUID] = ["FFF0", "FFE0", "18F0", "FFB0", "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2", "49535343-FE7D-4AE5-8FA9-9FAFD205E455"].map { CBUUID(string: $0) }

    var savedId: UUID? {
        get { UserDefaults.standard.string(forKey: "obdId").flatMap { UUID(uuidString: $0) } }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "obdId") }
    }
    var savedName: String {
        get { UserDefaults.standard.string(forKey: "obdName") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "obdName") }
    }

    func start() {
        if central != nil { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [
            CBCentralManagerOptionRestoreIdentifierKey: OBD.restoreId,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    // MARK: - Central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn {
            err = ""
            reconnectSaved()
        } else if c.state == .unauthorized {
            err = "Autorise le Bluetooth pour La Mathias dans Réglages."
            state = "off"
        } else if c.state == .poweredOff {
            err = "Active le Bluetooth de l’iPhone."
            state = "off"
        }
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let ps = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let p = ps.first {
            peripheral = p
            p.delegate = self
        }
    }

    /// Demande à iOS de se connecter au boîtier connu dès qu'il apparaît (pas de délai d'expiration).
    func reconnectSaved() {
        guard central != nil, central.state == .poweredOn, let id = savedId else { return }
        if let p = peripheral, p.identifier == id {
            if p.state == .connected {
                if writeChar == nil { state = "init"; p.discoverServices(nil) }
                return
            }
            if p.state == .connecting { if state != "ok" { state = "wait" }; return }
        }
        guard let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripheral = p
        p.delegate = self
        if state != "ok" { state = "wait" }
        central.connect(p, options: nil)
    }

    func scan() {
        guard central != nil, central.state == .poweredOn else {
            err = central?.state == .unauthorized ? "Autorise le Bluetooth pour La Mathias dans Réglages." : "Active le Bluetooth de l’iPhone."
            onFound?([], true)
            return
        }
        found = [:]
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
            guard let self = self else { return }
            if self.central.isScanning { self.central.stopScan() }
            self.emitFound(final: true)
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (ad[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        if name.isEmpty { return }
        found[p.identifier] = (p, rssi.intValue)
        emitFound(final: false)
    }

    private func emitFound(final: Bool) {
        let list = found.values.sorted { a, b in
            let oa = OBD.looksOBD(a.0.name ?? ""), ob = OBD.looksOBD(b.0.name ?? "")
            if oa != ob { return oa }
            return a.1 > b.1
        }.map { v -> [String: Any] in
            ["id": v.0.identifier.uuidString, "name": v.0.name ?? "?", "rssi": v.1, "obd": OBD.looksOBD(v.0.name ?? "")]
        }
        onFound?(list, final)
    }

    static func looksOBD(_ n: String) -> Bool {
        let s = n.lowercased()
        return ["obd", "elm", "vlink", "vgate", "icar", "v-link", "ios-vlink", "konnwei", "veepeak", "carista", "obdii", "obd2", "android-vlink"].contains { s.contains($0) }
    }

    func pick(_ idString: String) {
        guard let id = UUID(uuidString: idString) else { return }
        if central.isScanning { central.stopScan() }
        let p = found[id]?.0 ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let per = p else { return }
        if let old = peripheral, old.identifier != id { central.cancelPeripheralConnection(old) }
        savedId = id
        savedName = per.name ?? "OBD"
        peripheral = per
        per.delegate = self
        state = "conn"
        central.connect(per, options: nil)
    }

    func forget() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        savedId = nil
        savedName = ""
        peripheral = nil
        clearLink()
        state = "off"
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        state = "init"
        err = ""
        p.delegate = self
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        state = "wait"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.reconnectSaved() }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        let was = state == "ok"
        clearLink()
        state = savedId == p.identifier ? "wait" : "off"
        if was { onLost?() }
        if savedId == p.identifier { central.connect(p, options: nil) }
    }

    private func clearLink() {
        notifyChar = nil
        writeChar = nil
        timeoutItem?.cancel()
        let cb = current
        current = nil
        let q = queue
        queue = []
        cb?(nil)
        q.forEach { $0.cb(nil) }
        initToken += 1
    }

    // MARK: - Services

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        let svcs = p.services ?? []
        pendingServices = svcs.count
        if svcs.isEmpty { err = "Cet appareil n’est pas un adaptateur OBD reconnu."; central.cancelPeripheralConnection(p); return }
        for s in svcs { p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        pendingServices -= 1
        if pendingServices > 0 { return }
        let all = (p.services ?? []).flatMap { $0.characteristics ?? [] }
        func isN(_ c: CBCharacteristic) -> Bool { c.properties.contains(.notify) || c.properties.contains(.indicate) }
        func isW(_ c: CBCharacteristic) -> Bool { c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) }
        var n: CBCharacteristic? = nil
        var w: CBCharacteristic? = nil
        // d'abord un service connu des ELM327, sinon le premier service qui sait notifier et écrire
        let ordered = (p.services ?? []).sorted { a, b in known.contains(a.uuid) && !known.contains(b.uuid) }
        for s in ordered {
            let cs = s.characteristics ?? []
            if let nn = cs.first(where: isN), let ww = cs.first(where: isW) { n = nn; w = ww; break }
        }
        if n == nil { n = all.first(where: isN) }
        if w == nil { w = all.first(where: isW) }
        guard let nc = n, let wc = w else {
            err = "Cet appareil n’est pas un adaptateur OBD reconnu."
            central.cancelPeripheralConnection(p)
            return
        }
        notifyChar = nc
        writeChar = wc
        p.setNotifyValue(true, for: nc)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if c == notifyChar && c.isNotifying { elmInit() }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let v = c.value else { return }
        buf += String(decoding: v, as: UTF8.self)
        guard let r = buf.range(of: ">") else { return }
        let resp = String(buf[buf.startIndex..<r.lowerBound])
        buf = String(buf[r.upperBound...])
        guard let cb = current else { return }
        current = nil
        timeoutItem?.cancel()
        cb(resp)
        pump()
    }

    // MARK: - File de commandes ELM327

    func send(_ cmd: String, timeout: Double = 2.5, _ cb: @escaping (String?) -> Void) {
        guard writeChar != nil else { cb(nil); return }
        queue.append((cmd, timeout, cb))
        pump()
    }

    private func pump() {
        guard current == nil, !queue.isEmpty, let p = peripheral, let w = writeChar else { return }
        let item = queue.removeFirst()
        current = item.cb
        buf = ""
        let data = Array((item.cmd + "\r").utf8)
        let type: CBCharacteristicWriteType = w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let mx = max(20, min(180, p.maximumWriteValueLength(for: type)))
        var i = 0
        while i < data.count {
            let chunk = Data(data[i..<min(i + mx, data.count)])
            p.writeValue(chunk, for: w, type: type)
            i += mx
        }
        let t = DispatchWorkItem { [weak self] in
            guard let self = self, let cb = self.current else { return }
            self.current = nil
            cb(nil)
            self.pump()
        }
        timeoutItem = t
        DispatchQueue.main.asyncAfter(deadline: .now() + item.timeout, execute: t)
    }

    /// Octets d'une réponse OBD après l'en-tête (ex. "410C" → [0x1A, 0xF8]).
    static func bytes(_ r: String?, _ hdr: String) -> [Int]? {
        guard let r = r else { return nil }
        let s = r.uppercased().filter { !" \r\n>".contains($0) }
        guard let range = s.range(of: hdr) else { return nil }
        let h = Array(s[range.upperBound...])
        var out: [Int] = []
        var k = 0
        while k + 1 < h.count && out.count < 8 {
            guard let v = Int(String(h[k...k + 1]), radix: 16) else { break }
            out.append(v)
            k += 2
        }
        return out.isEmpty ? nil : out
    }

    /// PIDs pris en charge au-delà de 0x20 (0120, 0140…), pour trouver 015E (débit carburant) ou 0144 (richesse).
    private func moreSup(_ base: Int, _ done: @escaping () -> Void) {
        guard sup.contains(base) else { done(); return }
        let h = String(format: "%02X", base)
        send("01" + h, timeout: 4) { [weak self] r in
            guard let self = self else { return }
            guard let b = OBD.bytes(r, "41" + h), b.count >= 4 else { done(); return }
            for i in 0..<4 { for k in 0..<8 where b[i] & (128 >> k) != 0 { self.sup.insert(base + i * 8 + k + 1) } }
            self.moreSup(base + 32, done)
        }
    }

    /// 2.99 : protocole de la voiture retenu après la 1re connexion (ATDPN) → plus de recherche automatique lente au démarrage
    private var savedProto: String? {
        get { UserDefaults.standard.string(forKey: "elmProto") }
        set { UserDefaults.standard.set(newValue, forKey: "elmProto") }
    }
    private var protoFails = 0

    private func elmInit() {
        initToken += 1
        let tok = initToken
        state = "init"
        let sp = savedProto.map { "ATSP" + $0 } ?? "ATSP0"
        let seq: [(String, Double)] = [("ATZ", 3), ("ATE0", 2), ("ATL0", 2), ("ATS0", 2), ("ATH0", 2), ("ATAT2", 2), (sp, 2)]
        func step(_ i: Int) {
            if tok != initToken { return }
            if i < seq.count { send(seq[i].0, timeout: seq[i].1) { _ in step(i + 1) }; return }
            probe(tok, tries: 0)
        }
        step(0)
    }

    /// demande 0100 jusqu'à ce que la voiture réponde (contact mis), sans tout réinitialiser à chaque fois
    private func probe(_ tok: Int, tries: Int) {
        send("0100", timeout: savedProto != nil ? 6 : 15) { [weak self] r in
            guard let self = self, tok == self.initToken else { return }
            guard let b = OBD.bytes(r, "4100"), b.count >= 4 else {
                self.err = "L’adaptateur répond mais pas la voiture : contact mis ?"
                self.state = "noecu"
                // protocole retenu qui ne marche plus (2 réinitialisations complètes ratées) → on repasse en recherche auto
                if tries >= 4 { self.protoFails += 1; if self.protoFails >= 2 { self.savedProto = nil; self.protoFails = 0 } }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self, tok == self.initToken, self.writeChar != nil else { return }
                    if tries >= 4 { self.elmInit() } else { self.probe(tok, tries: tries + 1) }
                }
                return
            }
            self.protoFails = 0
            var s = Set<Int>()
            for i in 0..<4 { for k in 0..<8 where b[i] & (128 >> k) != 0 { s.insert(i * 8 + k + 1) } }
            self.sup = s
            self.moreSup(0x20) {
                self.send("ATDPN") { p in
                    let hex = (p ?? "").uppercased().filter { "0123456789ABCDEF".contains($0) }
                    if let last = hex.last { self.can = "6789AB".contains(last); self.savedProto = String(last) }
                    self.err = ""
                    self.state = "ok"
                    self.onReady?()
                }
            }
        }
    }
}
