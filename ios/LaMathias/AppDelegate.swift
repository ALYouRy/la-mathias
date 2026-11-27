import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Le Bluetooth doit être prêt dès le lancement : iOS relance l'appli en arrière-plan quand le boîtier OBD se réveille.
        // 2.100 : pourquoi l'appli démarre (ouverte par toi, réveillée par le boîtier, par la position…)
        var why = "ouverture"
        if launchOptions?[.bluetoothCentrals] != nil { why = "réveil par le Bluetooth (boîtier)" }
        else if launchOptions?[.location] != nil { why = "réveil par la position" }
        else if application.applicationState == .background { why = "réveil en arrière-plan" }
        LMLog.add("— Lancement de l'appli : " + why)
        Core.shared.start()
        LMHook.start = { Core.shared.rec.forceStart() }
        UNUserNotificationCenter.current().delegate = self
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = UIColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1)
        w.rootViewController = WebViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }

    /// 2.91 : liens des widgets (lamathias://conduite, lamathias://trajets, …)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        let p = (url.host ?? "") + url.path
        Core.shared.js("window.LMN&&LMN.open&&LMN.open('\(p.replacingOccurrences(of: "'", with: ""))')")
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
