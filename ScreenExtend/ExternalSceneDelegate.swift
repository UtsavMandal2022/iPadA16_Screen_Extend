import UIKit

/// The scene that appears on the HDMI monitor. It owns the full-resolution browser window.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Use the highest-resolution mode the display offers and draw edge to edge.
        // (Real HDMI displays usually report their native mode as preferred, but the
        // Simulator's virtual display prefers 720x480, so pick by pixel area instead.)
        let screen = windowScene.screen
        let best = screen.availableModes.max { a, b in
            a.size.width * a.size.height < b.size.width * b.size.height
        }
        if let best, screen.currentMode != best {
            screen.currentMode = best
        }
        screen.overscanCompensation = .none
        NSLog("SE external: bounds=%@ native=%@ scale=%.2f current=%@ preferred=%@ modes=%@ sceneBounds=%@",
              NSCoder.string(for: screen.bounds), NSCoder.string(for: screen.nativeBounds), screen.scale,
              screen.currentMode.map { NSCoder.string(for: $0.size) } ?? "nil",
              screen.preferredMode.map { NSCoder.string(for: $0.size) } ?? "nil",
              screen.availableModes.map { NSCoder.string(for: $0.size) }.joined(separator: ","),
              NSCoder.string(for: windowScene.coordinateSpace.bounds))

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = MonitorViewController()
        window.isHidden = false
        self.window = window
        BrowserModel.shared.externalDisplayConnected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        BrowserModel.shared.externalDisplayConnected = false
        BrowserModel.shared.monitorSize = nil
        window = nil
    }
}
