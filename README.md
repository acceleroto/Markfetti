<p align="center">
  <img src="graphics/markfetti-icon-256.png" width="128" height="128" alt="Markfetti app icon">
</p>

<h1 align="center">Markfetti</h1>

<p align="center">
  <b>A macOS Markdown viewer that renders <code>.md</code> files the way github.com does.</b><br>
  Math, Mermaid diagrams, alerts, maps and 3D models included.
</p>

<p align="center">
  <a href="https://github.com/acceleroto/Markfetti/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/acceleroto/Markfetti?label=download&color=8a3ffc"></a>
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-0a84ff?logo=apple&logoColor=white">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-ff2d95"></a>
</p>

**Supports:** CommonMark + GitHub Flavored Markdown (tables, task lists, strikethrough, autolinks), footnotes,
alerts (`> [!NOTE]` …), `:emoji:` shortcodes, heading anchors, syntax highlighting (~80 languages),
math (`$…$`, `` $`…`$ ``, `$$…$$`, ` ```math `), Mermaid diagrams, GeoJSON/TopoJSON maps, STL 3D models,
GitHub's HTML subset (`<details>`, `<picture>` with dark-mode sources, `<kbd>`, `align`, …) and light/dark mode.

**App features:** live reload when the file changes, relative images and links (including other `.md` files and
`file.md#section`), outline sidebar (⌃⌘S), view source (⌥⌘U), find (⌘F / ⌘G), zoom (⌘+ / ⌘− / ⌘0),
print and Export as PDF (⇧⌘E), tabs, Open Recent, and *Make Default Markdown Viewer* in the app menu.

## Install

Download `Markfetti-<version>.dmg` from the [latest release](https://github.com/acceleroto/Markfetti/releases/latest),
open it and drag **Markfetti** to **Applications**. It runs on macOS 13 or later, on Apple Silicon and Intel Macs.

The app isn't notarized by Apple yet, so the first time you open it macOS says it can't verify the developer:

1. Click **Done** (or **OK**) in that dialog.
2. Open **System Settings ▸ Privacy & Security**, scroll down and click **Open Anyway** next to Markfetti.
3. Confirm with your password. After this it opens normally.

Or, in Terminal: `xattr -dr com.apple.quarantine /Applications/Markfetti.app`

To make it your default Markdown viewer, choose **Markfetti ▸ Make Default Markdown Viewer**.

## Build

Requires Xcode (Swift 5.9+), macOS 13 or later.

```bash
./build.sh            # → build/Markfetti.app
./build.sh --install  # also copies it to /Applications
./scripts/make-dmg.sh # → build/Markfetti-<version>.dmg
```

All rendering libraries are vendored in `Resources/web/vendor` (pinned versions, fetched by
`scripts/fetch-vendor.sh`), so the app works offline. Only map tiles for GeoJSON/TopoJSON need the internet.

## Layout

| Path | What |
|---|---|
| `Sources/Markfetti/` | AppKit shell: document, window + WKWebView, file watcher, `markfetti://` scheme handler, menus |
| `Resources/web/render.js` | The Markdown → HTML pipeline (markdown-it → DOMPurify → KaTeX / Mermaid / Leaflet / three.js) |
| `Resources/web/app.css` | Page layout around `github-markdown.css` |
| `samples/kitchen-sink.md` | A test file that uses every feature |

To work on the renderer without rebuilding, serve the project folder (`python3 -m http.server 8765`) and open
<http://localhost:8765/Resources/web/index.html?file=/samples/kitchen-sink.md>.

The app only reads local files inside the open document's folder (or its git repository), and it strips
scripts, styles, iframes and forms from documents, as GitHub does.

## License

Markfetti is released under the [MIT License](LICENSE). The third-party libraries in
`Resources/web/vendor/` keep their own licenses (MIT, BSD, ISC, Apache-2.0/MPL-2.0); see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
