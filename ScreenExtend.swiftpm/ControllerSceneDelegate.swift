import UIKit
import SwiftUI

/// The scene shown on the iPad itself: trackpad, keyboard, URL bar, tabs.
final class ControllerSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ControllerView())
        window.makeKeyAndVisible()
        self.window = window
    }
}
