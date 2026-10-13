import SwiftUI
import UIKit

/// The iPad trackpad surface. One finger moves the cursor, tap clicks,
/// two-finger drag scrolls, two-finger tap sends Escape (exits fullscreen).
struct TrackpadView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemBackground
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.isMultipleTouchEnabled = true

        let move = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMove(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1

        let scroll = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTouchesRequired = 1

        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2

        [move, scroll, tap, twoFingerTap].forEach { view.addGestureRecognizer($0) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject {
        @objc func handleMove(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed, let view = gesture.view else { return }
            let t = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            BrowserModel.shared.moveCursor(by: t)
        }

        @objc func handleScroll(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed, let view = gesture.view else { return }
            let t = gesture.translation(in: view)
            gesture.setTranslation(.zero, in: view)
            BrowserModel.shared.scroll(by: t)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            BrowserModel.shared.click()
        }

        @objc func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            BrowserModel.shared.escape()
        }
    }
}

/// On-iPad preview of the active web view, shown only when no monitor is attached.
struct WebPreview: UIViewRepresentable {
    let webView: WKWebViewBox

    func makeUIView(context: Context) -> WebViewHost { WebViewHost() }

    func updateUIView(_ host: WebViewHost, context: Context) {
        // Never take the web view away from the monitor.
        host.webView = BrowserModel.shared.externalDisplayConnected ? nil : webView.value
    }

    static func dismantleUIView(_ host: WebViewHost, coordinator: ()) {
        host.webView = nil
    }
}

/// Tiny wrapper so SwiftUI compares web views by identity rather than structurally.
struct WKWebViewBox: Equatable {
    let value: WKWebView?
    static func == (lhs: WKWebViewBox, rhs: WKWebViewBox) -> Bool { lhs.value === rhs.value }
}

import WebKit
