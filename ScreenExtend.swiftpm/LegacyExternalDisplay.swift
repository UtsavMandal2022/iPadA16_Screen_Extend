import UIKit

/// Fallback for hosts that expose a second UIScreen but never create an
/// external-display scene for us (observed when running inside Swift Playgrounds).
/// Uses the pre-scene UIWindow.screen API, which is deprecated but still functional.
@MainActor
final class LegacyExternalDisplay {
    static let shared = LegacyExternalDisplay()
    private var window: UIWindow?
    private var observers: [NSObjectProtocol] = []

    @Published private(set) var screenCount = UIScreen.screens.count

    func start() {
        observers.append(NotificationCenter.default.addObserver(forName: UIScreen.didConnectNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let screen = note.object as? UIScreen else { return }
                self.screenCount = UIScreen.screens.count
                // Give UIKit a moment to deliver a proper scene first; only then fall back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.attachIfNeeded(screen) }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScreen.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.screenCount = UIScreen.screens.count
                if let screen = note.object as? UIScreen, self.window?.screen === screen { self.detach() }
            }
        })
        // HDMI may already be connected at launch.
        if let external = UIScreen.screens.first(where: { $0 !== UIScreen.main }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.attachIfNeeded(external) }
        }
    }

    private func attachIfNeeded(_ screen: UIScreen) {
        let model = BrowserModel.shared
        guard !model.externalDisplayConnected, window == nil, UIScreen.screens.contains(where: { $0 === screen }) else { return }
        NSLog("SE legacy: attaching window to external screen %@", NSCoder.string(for: screen.bounds))
        if let best = screen.availableModes.max(by: { $0.size.width * $0.size.height < $1.size.width * $1.size.height }),
           screen.currentMode != best {
            screen.currentMode = best
        }
        screen.overscanCompensation = .none
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.rootViewController = MonitorViewController()
        window.isHidden = false
        self.window = window
        model.externalDisplayConnected = true
        model.lastMessage = "Monitor attached via legacy screen API."
    }

    private func detach() {
        window?.isHidden = true
        window = nil
        let model = BrowserModel.shared
        model.externalDisplayConnected = false
        model.monitorSize = nil
    }
}
