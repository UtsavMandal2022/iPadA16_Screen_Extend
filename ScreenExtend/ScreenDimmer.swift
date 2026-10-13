import UIKit
import Combine

/// Dims the iPad screen while the monitor is in use. Brightness changes are a no-op in the Simulator.
@MainActor
final class ScreenDimmer: ObservableObject {
    @Published private(set) var isDimmed = false
    private var savedBrightness: CGFloat = 0.5

    private var controllerScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.session.role == .windowApplication }?
            .screen
    }

    func toggle() {
        guard let screen = controllerScreen else { return }
        if isDimmed {
            screen.brightness = savedBrightness
        } else {
            savedBrightness = screen.brightness
            screen.brightness = 0.03
        }
        isDimmed.toggle()
    }

    func restore() {
        guard isDimmed, let screen = controllerScreen else { return }
        screen.brightness = savedBrightness
        isDimmed = false
    }
}
