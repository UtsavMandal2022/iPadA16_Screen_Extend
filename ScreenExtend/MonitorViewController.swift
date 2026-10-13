import UIKit
import Combine
import WebKit

/// Hosts a web view and re-parents it on demand. Used by the monitor scene and
/// by the on-iPad preview when no external display is connected.
final class WebViewHost: UIView {
    var webView: WKWebView? {
        didSet {
            if let old = oldValue, old !== webView, old.superview === self {
                old.removeFromSuperview()
            }
            if let webView, webView.superview !== self {
                webView.removeFromSuperview()
                addSubview(webView)
            }
            setNeedsLayout()
        }
    }

    /// Re-parent the web view if another host took it in the meantime.
    func reattach() {
        if let webView, webView.superview !== self {
            webView.removeFromSuperview()
            addSubview(webView)
            webView.frame = bounds
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reattach()
        webView?.frame = bounds
    }
}

/// A simple arrow cursor drawn on the monitor.
final class CursorView: UIImageView {
    init() {
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
        super.init(image: UIImage(systemName: "cursorarrow", withConfiguration: config))
        tintColor = .white
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.9
        layer.shadowRadius = 1.5
        layer.shadowOffset = CGSize(width: 1, height: 1)
        sizeToFit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Root view controller of the external display window.
final class MonitorViewController: UIViewController {
    private let host = WebViewHost()
    private let cursorView = CursorView()
    private let placeholder = UILabel()
    private var bag = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        placeholder.text = "Screen Extend\nOpen a tab on the iPad to start browsing."
        placeholder.numberOfLines = 0
        placeholder.textAlignment = .center
        placeholder.textColor = .lightGray
        placeholder.font = .systemFont(ofSize: 28, weight: .medium)

        view.addSubview(placeholder)
        view.addSubview(host)
        view.addSubview(cursorView)

        let model = BrowserModel.shared
        // The monitor always wins ownership of the active web view while connected.
        // Dispatch async so this runs after SwiftUI has torn down the on-iPad preview.
        model.$activeTabID
            .combineLatest(model.$tabs, model.$externalDisplayConnected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let webView = model.activeTab?.webView
                    self.host.webView = webView
                    self.host.reattach()
                    self.placeholder.isHidden = webView != nil
                }
            }
            .store(in: &bag)

        model.$cursor
            .combineLatest(model.$cursorVisible)
            .receive(on: RunLoop.main)
            .sink { [weak self] point, visible in
                self?.positionCursor(point, visible: visible)
            }
            .store(in: &bag)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        host.frame = view.bounds
        placeholder.frame = view.bounds.insetBy(dx: 40, dy: 40)
        let model = BrowserModel.shared
        let sizeChanged = model.monitorSize != view.bounds.size
        model.monitorSize = view.bounds.size
        if sizeChanged { model.resetZoom() }
        positionCursor(BrowserModel.shared.cursor, visible: BrowserModel.shared.cursorVisible)
    }

    private func positionCursor(_ point: CGPoint, visible: Bool) {
        let bounds = view.bounds
        cursorView.frame.origin = CGPoint(x: bounds.width * point.x, y: bounds.height * point.y)
        cursorView.alpha = visible ? 1 : 0
        view.bringSubviewToFront(cursorView)
    }
}
