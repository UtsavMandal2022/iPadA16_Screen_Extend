import WebKit

enum WebViewFactory {

    /// Desktop Safari UA so sites serve their desktop layout on the big screen.
    static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

    @MainActor
    static func make(incognito: Bool, ruleList: WKContentRuleList?) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = incognito ? .nonPersistent() : .default()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Native fullscreen (AVKit) crashes inside an external-display window; the
        // bridge script re-implements fullscreen as CSS pinning instead.
        config.preferences.isElementFullscreenEnabled = false
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.defaultWebpagePreferences.preferredContentMode = .desktop

        let script = WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        if let ruleList {
            config.userContentController.add(ruleList)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = desktopUserAgent
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.backgroundColor = .black
        webView.isOpaque = true
        return webView
    }

    // MARK: - Ad / popup host blocking (small starter list)

    static let contentRulesIdentifier = "ScreenExtendBasicBlockList"

    static let contentRulesJSON = #"""
    [
      {"trigger":{"url-filter":"doubleclick\\.net","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"googlesyndication\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"adnxs\\.com","load-type":["third-party"]},"action":{"type":"block"}},
      {"trigger":{"url-filter":"popads\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"popcash\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"propellerads\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"exoclick\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"trafficjunky\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"juicyads\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"adsterra\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"onclickads\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"hilltopads\\.net"},"action":{"type":"block"}}
    ]
    """#

    @MainActor
    static func compileRuleList() async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: contentRulesIdentifier,
                encodedContentRuleList: contentRulesJSON
            ) { list, error in
                if let error { print("WebViewFactory: rule list compile failed: \(error)") }
                continuation.resume(returning: list)
            }
        }
    }

    // MARK: - JavaScript bridge injected into every frame

    /// Exposes `window.__se` so the native side can drive the page with a virtual
    /// cursor and keyboard. Calls that land on an <iframe> are forwarded into that
    /// frame via postMessage, so embedded video players still receive clicks.
    static let bridgeScript = #"""
    (function () {
      if (window.__se) { return; }

      var activeFrame = null;   // iframe element that received the last click, if any
      var lastHover = null;

      function fire(el, type, x, y, extra) {
        var init = { bubbles: true, cancelable: true, view: window, clientX: x, clientY: y,
                     screenX: x, screenY: y, button: 0, buttons: type === 'mousedown' ? 1 : 0 };
        if (extra) { for (var k in extra) { init[k] = extra[k]; } }
        try { el.dispatchEvent(new PointerEvent('pointer' + type.replace('mouse', ''), Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, init))); } catch (e) {}
        el.dispatchEvent(new MouseEvent(type, init));
      }

      function forward(frame, name, args) {
        try { frame.contentWindow.postMessage({ __se: name, args: args }, '*'); } catch (e) {}
      }

      function frameLocal(frame, x, y) {
        var r = frame.getBoundingClientRect();
        return [x - r.left, y - r.top];
      }

      function isEditable(el) {
        if (!el) { return false; }
        if (el.isContentEditable) { return true; }
        var t = el.tagName;
        return t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT';
      }

      function scrollableAncestor(el) {
        while (el && el !== document.body && el !== document.documentElement) {
          var cs = getComputedStyle(el);
          var oy = cs.overflowY, ox = cs.overflowX;
          var canY = (oy === 'auto' || oy === 'scroll') && el.scrollHeight > el.clientHeight + 1;
          var canX = (ox === 'auto' || ox === 'scroll') && el.scrollWidth > el.clientWidth + 1;
          if (canY || canX) { return el; }
          el = el.parentElement;
        }
        return null;
      }

      window.__se = {
        hover: function (x, y) {
          var el = document.elementFromPoint(x, y);
          if (el && el.tagName === 'IFRAME') {
            var p = frameLocal(el, x, y);
            forward(el, 'hover', p);
            return;
          }
          if (el !== lastHover) {
            if (lastHover) { fire(lastHover, 'mouseout', x, y); fire(lastHover, 'mouseleave', x, y); }
            if (el) { fire(el, 'mouseover', x, y); fire(el, 'mouseenter', x, y); }
            lastHover = el;
          }
          if (el) { fire(el, 'mousemove', x, y); }
        },

        click: function (x, y) {
          var el = document.elementFromPoint(x, y);
          if (!el) { return; }
          if (el.tagName === 'IFRAME') {
            activeFrame = el;
            var p = frameLocal(el, x, y);
            forward(el, 'click', p);
            return;
          }
          activeFrame = null;
          fire(el, 'mousemove', x, y);
          fire(el, 'mousedown', x, y);
          if (isEditable(el) && el.focus) { el.focus(); }
          else if (document.activeElement && document.activeElement !== el && !el.contains(document.activeElement)) {
            try { document.activeElement.blur(); } catch (e) {}
          }
          fire(el, 'mouseup', x, y);
          fire(el, 'click', x, y);
        },

        scroll: function (x, y, dx, dy) {
          var el = document.elementFromPoint(x, y);
          if (el && el.tagName === 'IFRAME') {
            var p = frameLocal(el, x, y);
            forward(el, 'scroll', [p[0], p[1], dx, dy]);
            return;
          }
          var target = el ? scrollableAncestor(el) : null;
          if (target) { target.scrollBy(dx, dy); } else { window.scrollBy(dx, dy); }
        },

        insertText: function (t) {
          if (activeFrame) { forward(activeFrame, 'insertText', [t]); return; }
          var el = document.activeElement;
          if (!isEditable(el)) { return; }
          var ok = false;
          try { ok = document.execCommand('insertText', false, t); } catch (e) {}
          if (!ok && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
            var s = el.selectionStart != null ? el.selectionStart : el.value.length;
            var e2 = el.selectionEnd != null ? el.selectionEnd : s;
            el.value = el.value.slice(0, s) + t + el.value.slice(e2);
            try { el.selectionStart = el.selectionEnd = s + t.length; } catch (e) {}
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }
        },

        deleteBackward: function (n) {
          if (activeFrame) { forward(activeFrame, 'deleteBackward', [n]); return; }
          var el = document.activeElement;
          if (!isEditable(el)) { return; }
          for (var i = 0; i < n; i++) {
            var ok = false;
            try { ok = document.execCommand('delete'); } catch (e) {}
            if (!ok && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
              var s = el.selectionStart != null ? el.selectionStart : el.value.length;
              if (s > 0) {
                el.value = el.value.slice(0, s - 1) + el.value.slice(s);
                try { el.selectionStart = el.selectionEnd = s - 1; } catch (e) {}
                el.dispatchEvent(new Event('input', { bubbles: true }));
              }
            }
          }
        },

        pressEnter: function () {
          if (activeFrame) { forward(activeFrame, 'pressEnter', []); return; }
          var el = document.activeElement || document.body;
          var init = { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 };
          var proceed = el.dispatchEvent(new KeyboardEvent('keydown', init));
          el.dispatchEvent(new KeyboardEvent('keypress', init));
          el.dispatchEvent(new KeyboardEvent('keyup', init));
          if (proceed && el.form && el.tagName === 'INPUT' && el.type !== 'textarea') {
            if (el.form.requestSubmit) { el.form.requestSubmit(); } else { el.form.submit(); }
          }
        },

        escape: function () {
          if (activeFrame) { forward(activeFrame, 'escape', []); }
          unpin();
          if (document.activeElement) { try { document.activeElement.blur(); } catch (e) {} }
        },

        fillScreen: function () {
          if (pinned) { unpin(); return 'unfilled'; }
          var vids = Array.prototype.slice.call(document.querySelectorAll('video'));
          if (!vids.length) {
            var frames = Array.prototype.slice.call(document.querySelectorAll('iframe'));
            frames.sort(function (a, b) { return (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight); });
            if (frames.length) { forward(frames[0], 'fillScreen', []); return 'frame'; }
            return 'novideo';
          }
          vids.sort(function (a, b) { return (b.clientWidth * b.clientHeight) - (a.clientWidth * a.clientHeight); });
          var v = vids[0];
          var player = v.closest('.html5-video-player, .video-js, .jwplayer, .plyr, .vjs-tech, [data-player], .player') || v;
          pin(player);
          return 'css';
        }
      };

      // ---- Fullscreen re-implementation --------------------------------------
      // Pinning an element over the whole viewport with CSS. All page-side
      // fullscreen APIs are redirected here so WebKit never opens AVKit.
      var pinned = null;

      function ensureStyle() {
        if (document.getElementById('__se_fill_style')) { return; }
        var st = document.createElement('style');
        st.id = '__se_fill_style';
        st.textContent =
          '.__se_fill{position:fixed!important;top:0!important;left:0!important;right:0!important;bottom:0!important;' +
          'width:100vw!important;height:100vh!important;max-width:none!important;max-height:none!important;' +
          'margin:0!important;padding:0!important;transform:none!important;z-index:2147483647!important;background:#000!important;}' +
          'video.__se_fill{object-fit:contain!important;}' +
          '.__se_hide{visibility:hidden!important;pointer-events:none!important;}' +
          '.__se_anc{transform:none!important;filter:none!important;perspective:none!important;contain:none!important;' +
          'overflow:visible!important;clip-path:none!important;backdrop-filter:none!important;}' +
          'html.__se_fill_active,html.__se_fill_active body{overflow:hidden!important;}';
        (document.head || document.documentElement).appendChild(st);
      }

      function fireFs(el) {
        try { document.dispatchEvent(new Event('fullscreenchange', { bubbles: true })); } catch (e) {}
        try { document.dispatchEvent(new Event('webkitfullscreenchange', { bubbles: true })); } catch (e) {}
        if (el) {
          try { el.dispatchEvent(new Event('fullscreenchange', { bubbles: true })); } catch (e) {}
          try { el.dispatchEvent(new Event('webkitfullscreenchange', { bubbles: true })); } catch (e) {}
          try { el.dispatchEvent(new Event('webkitbeginfullscreen')); } catch (e) {}
        }
        try { window.dispatchEvent(new Event('resize')); } catch (e) {}
      }

      var savedZoom = null;
      var touched = [];

      // Hide everything that is not an ancestor of the pinned element, and
      // neutralise ancestor transforms/overflow so position:fixed really fills the viewport.
      function isolate(el) {
        var node = el;
        while (node && node !== document.body && node.parentElement) {
          var parent = node.parentElement;
          for (var i = 0; i < parent.children.length; i++) {
            var sib = parent.children[i];
            if (sib !== node && sib.tagName !== 'SCRIPT' && sib.tagName !== 'STYLE') {
              sib.classList.add('__se_hide'); touched.push(sib);
            }
          }
          if (parent !== document.body) { parent.classList.add('__se_anc'); touched.push(parent); }
          node = parent;
        }
      }

      function pin(el) {
        if (!el || pinned === el) { return; }
        if (pinned) { unpin(); }
        ensureStyle();
        pinned = el;
        // Page zoom would scale 100vw beyond the viewport; park it at 1 while filled.
        savedZoom = document.documentElement.style.zoom || '';
        document.documentElement.style.zoom = 1;
        isolate(el);
        el.classList.add('__se_fill');
        document.documentElement.classList.add('__se_fill_active');
        fireFs(el);
        if (window.parent !== window) { try { window.parent.postMessage({ __se: 'pinFrame' }, '*'); } catch (e) {} }
      }

      function unpin() {
        if (!pinned) { return; }
        var el = pinned;
        pinned = null;
        el.classList.remove('__se_fill');
        for (var i = 0; i < touched.length; i++) { touched[i].classList.remove('__se_hide'); touched[i].classList.remove('__se_anc'); }
        touched = [];
        document.documentElement.classList.remove('__se_fill_active');
        if (savedZoom !== null) { document.documentElement.style.zoom = window.__seZoom || savedZoom; savedZoom = null; }
        try { el.dispatchEvent(new Event('webkitendfullscreen')); } catch (e) {}
        fireFs(el);
        if (window.parent !== window) { try { window.parent.postMessage({ __se: 'unpinFrame' }, '*'); } catch (e) {} }
      }

      function def(obj, name, getter) {
        try { Object.defineProperty(obj, name, { configurable: true, get: getter }); } catch (e) {}
      }
      def(document, 'fullscreenEnabled', function () { return true; });
      def(document, 'webkitFullscreenEnabled', function () { return true; });
      def(document, 'fullscreenElement', function () { return pinned; });
      def(document, 'webkitFullscreenElement', function () { return pinned; });
      def(document, 'webkitCurrentFullScreenElement', function () { return pinned; });
      def(document, 'webkitIsFullScreen', function () { return !!pinned; });
      document.exitFullscreen = function () { unpin(); return Promise.resolve(); };
      document.webkitExitFullscreen = function () { unpin(); };
      document.webkitCancelFullScreen = function () { unpin(); };
      Element.prototype.requestFullscreen = function () { pin(this); return Promise.resolve(); };
      Element.prototype.webkitRequestFullscreen = function () { pin(this); };
      Element.prototype.webkitRequestFullScreen = function () { pin(this); };
      if (window.HTMLVideoElement) {
        HTMLVideoElement.prototype.webkitEnterFullscreen = function () { pin(this); };
        HTMLVideoElement.prototype.webkitEnterFullScreen = function () { pin(this); };
        HTMLVideoElement.prototype.webkitExitFullscreen = function () { unpin(); };
        HTMLVideoElement.prototype.webkitExitFullScreen = function () { unpin(); };
        def(HTMLVideoElement.prototype, 'webkitSupportsFullscreen', function () { return true; });
        def(HTMLVideoElement.prototype, 'webkitDisplayingFullscreen', function () { return pinned === this; });
      }

      window.__se.pinFrameFrom = function (sourceWindow, on) {
        var frames = document.querySelectorAll('iframe');
        for (var i = 0; i < frames.length; i++) {
          if (frames[i].contentWindow === sourceWindow) { if (on) { pin(frames[i]); } else { unpin(); } return; }
        }
      };

      // Page zoom via CSS zoom on the root element: reflows the layout, unlike WKWebView.pageZoom.
      window.__se.setZoom = function (z) {
        window.__seZoom = z;
        if (pinned) { return; }   // applied again when fullscreen ends
        if (document.documentElement) { document.documentElement.style.zoom = z; }
      };
      document.addEventListener('DOMContentLoaded', function () {
        if (window.__seZoom) { document.documentElement.style.zoom = window.__seZoom; }
      });

      // Entry point used by native code: coordinates normalised to 0...1 of the
      // viewport, so page zoom and pinch zoom never affect hit testing.
      window.__se.norm = function (name, nx, ny) {
        var x = nx * window.innerWidth, y = ny * window.innerHeight;
        var rest = Array.prototype.slice.call(arguments, 3);
        return window.__se[name].apply(null, [x, y].concat(rest));
      };

      window.addEventListener('message', function (e) {
        var d = e.data;
        if (!d || typeof d !== 'object' || !d.__se) { return; }
        if (d.__se === 'pinFrame' || d.__se === 'unpinFrame') { window.__se.pinFrameFrom(e.source, d.__se === 'pinFrame'); return; }
        if (!window.__se[d.__se]) { return; }
        try { window.__se[d.__se].apply(null, d.args || []); } catch (err) {}
      });
    })();
    """#
}
