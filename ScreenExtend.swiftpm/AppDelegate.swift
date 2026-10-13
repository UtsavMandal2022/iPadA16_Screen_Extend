import UIKit

/// UIKit entry point. There is no Info.plist in a Playgrounds app package, so the
/// scene configuration (including the external-display scene) is declared in code here.
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
            let config = UISceneConfiguration(name: "External", sessionRole: connectingSceneSession.role)
            config.delegateClass = ExternalSceneDelegate.self
            return config
        }
        let config = UISceneConfiguration(name: "Controller", sessionRole: connectingSceneSession.role)
        config.delegateClass = ControllerSceneDelegate.self
        return config
    }
}
