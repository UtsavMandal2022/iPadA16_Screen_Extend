import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AudioManager.shared.configure()
        // The monitor shows the browser only while this app is in the foreground,
        // so never let the iPad auto-lock while we are running.
        application.isIdleTimerDisabled = true
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            return UISceneConfiguration(name: "External", sessionRole: connectingSceneSession.role)
        }
        return UISceneConfiguration(name: "Controller", sessionRole: connectingSceneSession.role)
    }
}
