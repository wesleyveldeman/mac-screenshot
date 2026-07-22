# LightSnap

A Lightshot-style screenshot tool for modern macOS, built natively in Swift/AppKit.
Runs natively on Apple Silicon and Intel (universal binary) and uses the modern
ScreenCaptureKit API — no deprecated capture calls, works on macOS 14 Sonoma,
macOS 15 Sequoia, and macOS 26 Tahoe.

## Features

- **Status bar icon** — LightSnap lives in the menu bar. **Left-click the icon to
  start an area capture**; right-click for the menu (full-screen capture,
  settings, quit).
- **Global hotkeys** — `⇧⌘9` capture area, `⌥⇧⌘9` capture full screen by
  default, both configurable in Settings (click the shortcut field and type a
  new combination). Works from any app, no Accessibility permission needed.
- **Lightshot-style area selection** — the screen freezes, you drag to select.
  The selection shows live pixel dimensions and can be moved and resized with
  8 drag handles afterwards.
- **Edit in place** — annotate the selection before exporting:
  - Pen (freehand, smoothed)
  - Line
  - Arrow
  - Rectangle
  - Marker/highlighter (translucent, multiply blend)
  - Text
  - 8-color palette, undo/redo
- **Output** — copy to clipboard (`⌘C` or `Enter`), save with dialog (`⌘S`),
  instant save to your screenshots folder (`⇧⌘S`), print (`⌘P`).
- **Multi-display support** — every screen gets an overlay; select on whichever
  one you want. Retina-exact output (full pixel density, correct DPI metadata).
- **Settings** — save folder, PNG/JPEG, include cursor, launch at login,
  custom shortcuts, and an "After selection" action: show the editing tools
  (default), copy to clipboard immediately, or save to your folder immediately
  for a zero-keystroke workflow. With auto-copy/save enabled, hold `⌥` while
  releasing the selection to open the editor for that one capture.

Like Lightshot, everything happens on a frozen snapshot of your screen, so
menus, tooltips, and other transient UI can be captured too.

> Lightshot's cloud features (upload to prnt.sc and Google reverse-image
> search) depend on Lightshot's servers and are intentionally not included —
> LightSnap is fully offline and never sends your screenshots anywhere.

## Requirements

- macOS 14 (Sonoma) or later — including Apple Silicon Macs
- Xcode 15+ command line tools to build (`xcode-select --install` is not
  enough for universal builds; install Xcode from the App Store)

## Build & run

```sh
make run        # builds dist/LightSnap.app (universal) and opens it
```

Other targets:

```sh
make app              # just build the .app bundle
make ARCH_FLAGS=      # build for the host architecture only
make clean
```

The app appears as a camera icon in the menu bar. There is no Dock icon
(it's a background agent app).

### First run: Screen Recording permission

macOS requires Screen Recording permission for any screenshot app. On first
launch LightSnap requests it; enable **LightSnap** under
**System Settings → Privacy & Security → Screen Recording** and relaunch the
app if needed.

> Note: the Makefile signs the app ad-hoc by default. If you rebuild, macOS
> may ask for the permission again because the code signature changed. Sign
> with a real developer identity (see below) to avoid this.

### macOS blocks the app ("unknown developer")

Gatekeeper only screens apps that carry the quarantine flag, which macOS puts
on anything downloaded from the internet — a CI artifact, a zip from a
browser, an AirDropped copy. An app you build yourself with `make run` starts
without any prompt. For a downloaded copy you have three options, from
quick-and-dirty to correct:

1. **Remove the quarantine flag** (your own machine only):

   ```sh
   xattr -dr com.apple.quarantine /path/to/LightSnap.app
   ```

2. **Approve it once in the UI** — macOS 15 and later: try to open the app,
   then System Settings → Privacy & Security → scroll down → **Open Anyway**.
   macOS 14 and earlier: right-click the app → Open → Open.

3. **Sign and notarize properly** (needed to distribute to other people).
   This requires a paid Apple Developer membership:

   ```sh
   # one-time: store notarization credentials in the keychain
   xcrun notarytool store-credentials lightsnap \
     --apple-id you@example.com --team-id TEAMID99 \
     --password <app-specific-password>

   # sign with hardened runtime, notarize, staple, and produce dist/LightSnap.zip
   make release SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID99)"
   ```

   The resulting zip opens cleanly on any Mac. A stable Developer ID
   signature also stops macOS from re-asking for the Screen Recording
   permission after every rebuild.

## Publishing a release

Tag a version and push the tag — the Release workflow builds the universal
bundle and publishes `LightSnap-vX.Y.Z.zip` as a GitHub release, with the
app's version stamped from the tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The release zip is ad-hoc signed unless you build and upload one yourself
with `make release SIGN_IDENTITY=…`, so downloaders need the one-time
Gatekeeper approval described above.

## Usage

| Action | How |
| --- | --- |
| Capture an area | Click the menu bar icon, or `⇧⌘9` (configurable) |
| Capture full screen | Right-click icon → Capture Full Screen, or `⌥⇧⌘9` (configurable) |
| Open editor despite auto-copy/save | Hold `⌥` while releasing the selection |
| Select whole screen while capturing | `⌘A` |
| Move / resize selection | Drag inside it (with Select tool) / drag the handles |
| Annotate | Pick a tool + color in the toolbar, draw inside the selection |
| Add text | Text tool, click in the selection, type, press Enter |
| Undo / redo | `⌘Z` / `⇧⌘Z` |
| Copy to clipboard | `Enter`, `⌘C`, or toolbar button |
| Save with dialog | `⌘S` |
| Save instantly to folder | `⇧⌘S` |
| Print | `⌘P` |
| Cancel | `Esc` |

## Project layout

```
Sources/LightSnap/
  main.swift               entry point (agent app, no Dock icon)
  AppDelegate.swift        status bar item, menu, hotkey registration
  HotkeyManager.swift      Carbon global hotkeys (no Accessibility permission)
  Hotkey.swift             hotkey model + HotkeyCenter registration hub
  HotkeyRecorderField.swift  click-to-record shortcut field for Settings
  ScreenCapturer.swift     ScreenCaptureKit screenshots of every display
  CaptureController.swift  capture session lifecycle
  OverlayWindow.swift      borderless full-screen overlay window
  SelectionView.swift      selection, editing, keyboard handling, export
  Annotations.swift        annotation model + shared renderer (screen & export)
  EditorToolbar.swift      floating tool/color/action bar
  OutputActions.swift      clipboard, save dialog, quick save, print
  Preferences.swift        UserDefaults-backed settings
  PreferencesWindow.swift  settings window
Support/Info.plist         app bundle metadata (LSUIElement agent app)
Makefile                   universal build + .app bundling + ad-hoc signing
```

## Troubleshooting

- **Hotkeys don't fire** — another app may already own the combination
  (Settings shows a warning when registration fails). Record a different
  shortcut in LightSnap's Settings, or change the other app's.
- **Black screenshots / permission alert loops** — remove LightSnap from the
  Screen Recording list in System Settings, re-add it, and relaunch.
- **"Launch at login" fails** — that feature requires running from the built
  `.app` bundle (`make run`), not the bare `swift run` executable.
