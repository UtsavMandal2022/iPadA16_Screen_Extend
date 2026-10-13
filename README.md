# Screen Extend

Full-screen browser on an HDMI monitor from an iPad that only supports mirroring
(A16 iPad, 11th gen). The monitor shows the web page at native resolution; the iPad
screen becomes a trackpad, keyboard, URL bar and tab switcher.

Built with Xcode (`ScreenExtend.xcodeproj`). A Swift Playgrounds version was tried and
abandoned: apps running inside Playgrounds never see the external display
("iOS reports 1 screen"), so a Mac with Xcode is required to install this.

## How it works

iPadOS lets any app claim an external display through the
`UIWindowSceneSessionRoleExternalDisplayNonInteractive` scene role. This app opens a
second window on the monitor containing a `WKWebView`, and drives that page from the
iPad with a virtual cursor (JavaScript bridge injected into every frame).

* `AppDelegate` / `Info.plist` – declare the two scenes (iPad window and external display).
* `ExternalSceneDelegate` / `MonitorViewController` – the monitor window.
* `ControllerSceneDelegate` / `ControllerView` – the iPad UI.
* `BrowserModel` – tabs, cursor, typing, popup blocking, private mode (shared singleton).
* `LibraryStore` / `LibraryView` – bookmarks and history.
* `WebViewFactory` – web view configuration, desktop UA, ad host block list, JS bridge.

## Run in the Simulator

1. Open `ScreenExtend.xcodeproj` in Xcode 26.
2. Pick the **iPad (A16)** simulator and press Run.
3. In the Simulator menu choose **I/O ▸ External Displays ▸ 3840×2160 (4K)**. Use 4K
   rather than 1080p: the Simulator's 1080p virtual display reports 720×480 as its
   only usable mode and ignores mode changes. Real HDMI monitors report their native
   resolution. iOS may show a "Stage Manager with an External Display" sheet once;
   tap *Use Screen Mirroring*.
4. With no external display attached the iPad shows a live preview instead, so the
   app is usable while developing.

## Run on the iPad (Mac with Xcode, USB once)

1. iPad: Settings ▸ Privacy & Security ▸ Developer Mode ▸ on (restarts once).
   Developer Mode is required for every Xcode install, cable or Wi-Fi.
2. Xcode ▸ Settings ▸ Accounts: sign in with your own Apple ID (free is fine).
3. Project ▸ target ▸ Signing & Capabilities: tick automatic signing and pick your
   Personal Team. Change the bundle identifier if Xcode says it is taken.
4. Plug the iPad in, tap Trust on the iPad, choose it as the destination, press Run.
5. First launch: iPad Settings ▸ General ▸ VPN & Device Management ▸ trust your Apple ID.
6. After the first cable connection, Xcode ▸ Window ▸ Devices and Simulators lets you
   tick *Connect via network* so later installs work over Wi-Fi.

Free Apple ID builds stop launching after 7 days; press Run again to refresh them.
A paid developer account removes the limit and allows TestFlight installs with no Mac.

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
* **Scenes are declared both in Info.plist and in code** (`UISceneConfiguration.delegateClass`),
  so the app also works when built without the plist.

## Known limits

* iPadOS returns the monitor to mirroring as soon as this app leaves the foreground.
* DRM video (Netflix, Prime, Disney+) may refuse to play in an embedded web view.
* The Simulator cannot test audio routing or DRM; use the real iPad for those.
