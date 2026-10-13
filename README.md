# Screen Extend

Full-screen browser on an HDMI monitor from an iPad that only supports mirroring
(A16 iPad, 11th gen). The monitor shows the web page at native resolution; the iPad
screen becomes a trackpad, keyboard, URL bar and tab switcher.

The project is a **Swift Playgrounds app package** (`ScreenExtend.swiftpm`). It opens
in Swift Playgrounds on the iPad itself, so no Mac or cable is needed, and it also
opens directly in Xcode on a Mac.

## How it works

iPadOS lets any app claim an external display through the
`UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene role. This app opens a
second window on the monitor containing a `WKWebView`, and drives that page from the
iPad with a virtual cursor (JavaScript bridge injected into every frame).

* `AppDelegate` – declares the two scenes in code (Playgrounds has no Info.plist).
* `ExternalSceneDelegate` / `MonitorViewController` – the monitor window.
* `ControllerSceneDelegate` / `ControllerView` – the iPad UI.
* `BrowserModel` – tabs, cursor, typing, popup blocking, private mode (shared singleton).
* `LibraryStore` / `LibraryView` – bookmarks and history.
* `WebViewFactory` – web view configuration, desktop UA, ad host block list, JS bridge.

## Run on the iPad with Swift Playgrounds (no Mac needed)

1. Install **Swift Playgrounds** from the App Store on the iPad.
2. In Safari on the iPad open this repository, tap **Code ▸ Download ZIP**.
3. Open the **Files** app, go to Downloads, tap the zip to unzip it, open the folder
   and tap **ScreenExtend.swiftpm**. It opens in Swift Playgrounds.
   (If it does not, long-press it, choose Share, then Swift Playgrounds.)
4. In Playgrounds press **Run**. Playgrounds builds the app and runs it full screen.
5. With the app running, connect the HDMI adapter. The monitor should switch from
   mirroring to the browser and the iPad should show the trackpad.

Notes on this route:

* Apps run from Playgrounds live inside Playgrounds. They are not installed to the
  Home Screen; you reopen them by pressing Run again. Installing to the Home Screen
  needs TestFlight or Xcode, both of which need a Mac and/or a paid developer account.
* Whether an app run from Playgrounds is allowed to take over the external display has
  not been verified on hardware yet. It works in the iOS Simulator build of this
  package. If the monitor keeps mirroring, the fallback is a Mac with Xcode (below).
* Playgrounds packages cannot ship an Info.plist, so plain `http://` sites may be
  blocked by App Transport Security. Nearly every video site uses `https://`.

## Run from a Mac with Xcode

1. Open `ScreenExtend.swiftpm` in Xcode 26 (File ▸ Open, pick the folder).
2. Simulator: pick **iPad (A16)**, press Run, then in the Simulator menu choose
   **I/O ▸ External Displays ▸ 3840×2160 (4K)**. Use 4K rather than 1080p: the
   Simulator's 1080p virtual display reports 720×480 as its only usable mode. Real HDMI
   monitors report their native resolution. iOS may show a "Stage Manager with an
   External Display" sheet once; tap *Use Screen Mirroring*.
3. Device: iPad Settings ▸ Privacy & Security ▸ Developer Mode on; Xcode ▸ Settings ▸
   Accounts, sign in with an Apple ID; set your Team in the package's signing settings;
   plug the iPad in, pick it as destination, press Run. Free Apple ID builds stop
   launching after 7 days; press Run again to refresh.

With no external display attached the iPad shows a live preview instead, so the app
is usable while developing.

## Controls

| On the iPad                      | On the monitor                         |
|----------------------------------|----------------------------------------|
| One-finger drag                  | Move cursor                            |
| Tap                              | Click                                  |
| Two-finger drag                  | Scroll                                 |
| Two-finger tap / Esc             | Exit fullscreen, unfocus field         |
| Type in the bottom field         | Types into the focused web input       |
| Return                           | Enter / submit form                    |
| ⤢ button                         | Fill the monitor with the video player |
| −  %  +                          | Page zoom (defaults to 200% on 4K)     |
| Speaker button                   | Choose audio output (iPad, headphones, HDMI) |
| Moon button                      | Dim the iPad screen                    |
| ★ star                           | Bookmark / unbookmark the current page |
| Book                             | Library: bookmarks, history, clear data|
| Eyeglasses (purple = on)         | Private browsing toggle (default on)   |

## Private browsing, bookmarks, history

* **Private browsing** is on by default (purple eyeglasses). New tabs then use a
  non-persistent WebKit store: no cookies, cache or logins survive closing the tab, and
  nothing is written to history. Turn it off to get a normal browser: logins persist and
  pages are recorded in History. The setting is remembered; existing tabs keep the mode
  they were opened in (the status row shows "Private" for the current tab).
* **Bookmarks** work in both modes. Tap the star; manage them in the Library.
* **History** lists pages visited in non-private tabs, searchable, swipe to delete.
  The Library menu can clear history and wipe cookies/site data for normal tabs.
* Typing in the address bar shows matching bookmarks and history as chips.
* Data lives in the app's Application Support folder as JSON; deleting the app removes it.

## Implementation notes

* **Fullscreen is emulated.** WebKit hands `<video>` fullscreen to AVKit's native
  player, which crashes inside a non-interactive external-display window. The bridge
  script overrides every fullscreen API (`requestFullscreen`, `webkitEnterFullscreen`,
  `exitFullscreen`, …) and instead pins the player element over the viewport with CSS,
  hiding its siblings. Sites see `fullscreenElement`/`fullscreenchange` as usual.
* **Zoom is CSS zoom** on the root element, applied after each navigation.
  `WKWebView.pageZoom` scales without reflowing in desktop content mode.
* **Cursor coordinates are normalised** (0…1) and resolved to CSS pixels inside the
  page, so zoom never breaks hit testing.
* **Display mode**: the external scene picks the largest `availableModes` entry
  rather than `preferredMode`.
* **Scenes are declared in code** via `UISceneConfiguration.delegateClass`, because a
  Playgrounds package cannot contain an Info.plist.

## Known limits

* iPadOS returns the monitor to mirroring as soon as this app leaves the foreground.
* DRM video (Netflix, Prime, Disney+) may refuse to play in an embedded web view.
* The Simulator cannot test audio routing or DRM; use the real iPad for those.
