import UIKit
import WebKit

/// Affiche La Mathias (le site, toujours à jour) et fait le lien avec la partie native (OBD, GPS en arrière-plan).
final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let site = URL(string: "https://alyoury.github.io/la-mathias/?app=ios")!
    private var web: WKWebView!
    private let errorView = UIView()
    private let errorLabel = UILabel()

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func loadView() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let ucc = WKUserContentController()
        ucc.add(WeakHandler(self), name: "lm")
        ucc.addUserScript(WKUserScript(source: "window.LM_NATIVE={v:1,platform:'ios'};", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = self
        w.uiDelegate = self
        w.isOpaque = false
        w.backgroundColor = UIColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1)
        w.scrollView.backgroundColor = w.backgroundColor
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.allowsBackForwardNavigationGestures = false
        if #available(iOS 16.4, *) { w.isInspectable = true }
        web = w
        view = w
        Core.shared.web = self
        buildErrorView()
        w.load(URLRequest(url: WebViewController.site, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func becameActive() {
        Core.shared.rec.pushLive()
        run("window.LMN&&LMN.tripsReady()")
    }

    func run(_ code: String) {
        guard web != nil else { return }
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    // MARK: - Messages de la page

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let op = m["op"] as? String else { return }
        let core = Core.shared
        switch op {
        case "hello":
            if let s = m["set"] as? [String: Any] { core.rec.setSettings(s) }
            core.rec.pushLive()
        case "perm":
            core.rec.askPermissions()
        case "scan":
            core.rec.askPermissions()
            core.obd.onFound = { list, final in core.js("window.LMN&&LMN.found(" + Core.json(list) + "," + (final ? "true" : "false") + "," + Core.json([core.obd.err]) + ")") }
            core.obd.scan()
        case "pick":
            if let id = m["id"] as? String { core.obd.pick(id) }
        case "forget":
            core.obd.forget()
            core.rec.pushLive()
        case "reconnect":
            core.obd.reconnectSaved()
        case "cmd":
            let id = (m["id"] as? NSNumber)?.intValue ?? 0
            let c = (m["c"] as? String) ?? ""
            let ms = (m["ms"] as? NSNumber)?.doubleValue ?? 2500
            core.obd.send(c, timeout: ms / 1000) { r in
                let arr: String = r != nil ? Core.json([r!]) : "[null]"
                core.js("window.LMN&&LMN.res(\(id)," + arr + ")")
            }
        case "end":
            core.rec.endTrip()
        case "set":
            core.rec.setSettings(m)
        case "trips":
            core.js("window.LMN&&LMN.trips(" + Core.json(Store.all()) + ")")
        case "ack":
            if let ids = m["ids"] as? [NSNumber] { Store.ack(ids.map { $0.doubleValue }) }
        case "island":
            let st = InfoAttributes.ContentState(icon: (m["icon"] as? String) ?? "car", title: (m["title"] as? String) ?? "", sub: (m["sub"] as? String) ?? "",
                                                 right: (m["right"] as? String) ?? "", tone: (m["tone"] as? String) ?? "info", progress: (m["progress"] as? NSNumber)?.doubleValue)
            LiveAct.shared.info(st, seconds: ((m["ms"] as? NSNumber)?.doubleValue ?? 3000) / 1000)
        case "gps":
            let vc = GPSViewController()
            vc.range = (m["range"] as? NSNumber)?.doubleValue
            vc.modalPresentationStyle = .fullScreen
            if presentedViewController == nil { present(vc, animated: true) }
        case "settings":
            if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
        default:
            break
        }
    }

    // MARK: - Navigation

    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = a.request.url else { decisionHandler(.allow); return }
        let s = u.scheme ?? ""
        if s == "http" || s == "https" || s == "about" || s == "blob" || s == "data" {
            // liens externes (App Store, Waze, cartes…) : dans Safari ou l'appli concernée
            if a.navigationType == .linkActivated, u.host != WebViewController.site.host {
                UIApplication.shared.open(u)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
            return
        }
        UIApplication.shared.open(u)
        decisionHandler(.cancel)
    }

    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = a.request.url { UIApplication.shared.open(u) }
        return nil
    }

    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { errorView.isHidden = true }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) { showError(e) }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { showError(e) }
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) { w.reload() }

    // Autorisations caméra / micro demandées par la page (scan des QR)
    func webView(_ w: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.grant)
    }

    func webView(_ w: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(a, animated: true)
    }

    func webView(_ w: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Annuler", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }

    // MARK: - Écran « pas de connexion »

    private func buildErrorView() {
        errorView.backgroundColor = web.backgroundColor
        errorView.isHidden = true
        errorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(errorView)
        NSLayoutConstraint.activate([
            errorView.leadingAnchor.constraint(equalTo: view.leadingAnchor), errorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorView.topAnchor.constraint(equalTo: view.topAnchor), errorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        errorLabel.textColor = .white
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.font = .systemFont(ofSize: 17)
        let b = UIButton(type: .system)
        b.setTitle("Réessayer", for: .normal)
        b.titleLabel?.font = .boldSystemFont(ofSize: 18)
        b.addTarget(self, action: #selector(retry), for: .touchUpInside)
        let st = UIStackView(arrangedSubviews: [errorLabel, b])
        st.axis = .vertical
        st.spacing = 18
        st.translatesAutoresizingMaskIntoConstraints = false
        errorView.addSubview(st)
        NSLayoutConstraint.activate([
            st.centerYAnchor.constraint(equalTo: errorView.centerYAnchor),
            st.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 30),
            st.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -30),
        ])
    }

    private func showError(_ e: Error) {
        if (e as NSError).code == NSURLErrorCancelled { return }
        errorLabel.text = "La Mathias n’arrive pas à se charger.\nVérifie la connexion internet.\n\nL’enregistrement des trajets continue quand même."
        errorView.isHidden = false
    }

    @objc private func retry() {
        errorView.isHidden = true
        web.load(URLRequest(url: WebViewController.site, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 20))
    }
}

/// Évite que la page garde l'écran en mémoire (cycle WKUserContentController → handler).
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}
