# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

There is no Xcode project; the app is compiled directly with `swiftc` via a shell script.

```bash
./build.sh        # compiles all .swift files into PhotoPrint.app, symlinks to ~/Applications
open PhotoPrint.app
```

`build.sh` lists every source file explicitly in its `swiftc` invocation — **when you add a new `.swift` file you must add it to the compile line in `build.sh`**, or it won't be included. Files are compiled with `-parse-as-library -O`. There is no test suite, linter, or package manager.

Releases are built, notarized, and tagged locally before pushing:
1. Run `./build-release.sh <version>` (e.g., `./build-release.sh 1.0.12`). This compiles, signs (with Hardened Runtime), notarizes via Apple Notary Service, staples the notarization ticket, and stages the changes (`PhotoPrint.app` and `Info.plist`) in Git.
2. Commit, tag, and push:
   ```bash
   git commit -m "Release v1.0.12"
   git tag v1.0.12
   git push origin main v1.0.12
   ```
Pushing the `v*` tag triggers `.github/workflows/release.yml`, which packages the committed and notarized `PhotoPrint.app` bundle and attaches it as a GitHub Release asset. The built app bundle is intentionally committed to the repo for this reason.

## Platform note

`Info.plist` sets `LSMinimumSystemVersion` to **26.0** (macOS 26 "Tahoe"). The UI relies on macOS 26 "Liquid Glass" window styling and a fully custom borderless window with hand-drawn traffic-light controls, so it targets macOS 26+. Build with the Xcode Command Line Tools `swiftc`; there is no Xcode project.

## Architecture

A SwiftUI macOS app with no Xcode-managed assets. Six source files, all in the repo root. The non-obvious flow is the **two-stage rendering pipeline** that separates layout math from pixel compositing.

**Data flow:** user picks a directory → `ImageCompositor.getDimensionsAndTag` reads each file's pixel dimensions (corrected for EXIF orientation) and Finder color tag → these become `ImageFile` models → `LayoutEngine` computes a fitting arrangement → `ImageCompositor.buildComposite` rasterizes the chosen page → saved as TIFF → `PrinterManager` shells out to `lp`.

### Layout engine (`LayoutEngine.swift`)
Pure value-type logic, no UI. Images are scaled so their *longer* dimension equals `config.longerDim` (the "Image Scale" slider), preserving aspect ratio. `calculateLayout` simulates **both** landscape and portrait orientations (a greedy row-packing fill with `minGap` = 0.15"), then picks the orientation that fits the page height — or, if both/neither fit, the one with the smaller total height. `wouldFit` is what drives the per-image checkbox enable/disable in the UI. All dimensions here are in **inches**.

### Compositor (`ImageCompositor.swift`)
Converts the inch-based `LayoutResult` into pixels at `config.dpi` (300) using a Core Graphics bitmap context. Rotates individual images 90° when their natural orientation doesn't match the page orientation, and distributes whitespace evenly as gaps between rows and between items in a row. `useThumbnails: true` loads downscaled images for fast on-screen preview; `useThumbnails: false` loads full-resolution for the actual print. Output is written as a lossless TIFF with embedded DPI metadata.

### Printing (`PrinterManager.swift`)
A thin wrapper that shells out to the CUPS CLI tools via `Process`: `lpstat -p` (discover printers), `lpoptions -p <printer> -l` (parse available `MediaType` / `InputSlot` choices dynamically per printer), and `lp` (submit the TIFF with `PageSize`/`InputSlot`/`MediaType` options). All output is parsed from stdout text.

### UI (`ContentView.swift`, `PhotoPrintApp.swift`)
`ContentView` is a large single view holding all `@State` (selected directory, images, `PrintConfig`, batch pages, print status). Two distinct print modes share the UI:
- **Single-page**: print the manually `isSelected` images.
- **Auto-batch** (`autoBatchAll`): greedily packs *all* unprinted images across multiple `autoBatchedPages`, paginated below the canvas. After a page prints successfully it is removed from `autoBatchedPages`.

`ImageCache` (an `NSCache<NSString, NSImage>`) plus async thumbnail loading on `DispatchQueue.global(qos: .userInitiated)` keeps sidebar scrolling fluid with large directories. All heavy work (loading dirs, compositing, printing) runs off the main thread and marshals UI updates back via `DispatchQueue.main.async`.

`PhotoPrintApp.swift` builds a custom chromeless `NSWindow` (`LiquidGlassWindow`), a `BorderlessResizeView` for edge-drag resizing, and `WindowControls` for the custom traffic lights — this is why the app owns its window appearance rather than using a stock SwiftUI `WindowGroup` chrome.

`Models.swift` defines all shared value types: `ImageFile`, `PrintConfig`, `PaperPreset` (the paper-size dropdown presets, including their CUPS `PageSize` strings), `LayoutItem`, and `LayoutResult`.
