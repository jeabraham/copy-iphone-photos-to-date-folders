# Photo Importer (macOS app) — specification

A single-window macOS app that wraps the existing import tools. Nothing is ever deleted
from any source.

- Minimum macOS: **15 (Sequoia)**, the newest release the 2017 iMac Pro supports.
- Distribution: Developer ID signed, hardened runtime, notarized, not sandboxed.

## Code sharing

| Piece | Standalone tool (unchanged workflow) | In the app |
|---|---|---|
| iPhone import (direct and companion) | `copy-iphone-photos.swift` run with `swift` | The same file, compiled into the app |
| Memory card import | `copy-sd-photos.sh` (kept simple) | `CardImporter.swift`, a Swift port with the app's extra settings |

The app never runs shell scripts or the `swift` interpreter.

`copy-iphone-photos.swift` stays a runnable script. At build time
`macos-app/Scripts/make-importer-core.sh` copies it to `PhotoImporter/Generated/ImporterCore.swift`
(dropping the shebang and everything from the `// MARK: script entry point` line on) and the
app compiles that with `-D IMPORTER_LIBRARY`. In that mode the file's `print` and error output go
to hooks (`importerOutputSink`, `importerErrorSink`), `importerCancelled` is polled, and
`Importer` can run non-blocking via `start()` / `cancel()` / `onFinish`. Keep the marker line in the script.

Device identity is the importer's own: `serial:<serial>` (or `manual:<id>`), with the
Image Capture / companion UDID normalisation. The app does not duplicate it; it stores only the
ImageCaptureCore device name (passed as `--device`) and a user-defined label.

## Persistence

- App defaults: only the last destination path.
- Everything else is in the destination's `.iphone-import.sqlite3`, in app-owned tables
  `app_settings` and `app_sources`. The importer's schema (`user_version` 1) is unchanged.
  When the app creates settings in a new database it first creates the importer's tables through
  `PhotoInventory`, so dry runs against it work.
- Choosing a destination with no app settings prompts: create settings? and keep the memory
  cards, iPhones and settings from the previous destination? The photo inventory is never copied.

## Screen

1. **Import destination** — choose folder; **From / To** dates, prominent, saved per destination
   (inclusive, optional); **Settings**: include videos, overwrite, dry run, adopt existing.
   Sections 2 and 3 appear only once a destination is chosen.
2. **Memory cards** — "+" adds a card folder. Row buttons: Settings (per-card overrides of dry
   run, overwrite, include videos, defaulting to the destination), Show (Finder), Update
   location, Import, Delete (removes the row and its settings only).
3. **iPhones** — "+" opens a wizard that waits for a USB-connected iPhone and shows
   troubleshooting (unplug others, unlock, tap Trust, close Lightroom / Image Capture / Photos
   import windows, companion app open with Full Access to Photos — that permission is for the
   iOS companion app only). The user names the phone (e.g. "John's iPhone"). Row buttons:
   Settings, Update (re-run wizard), Import directly (Image Capture), Import via app
   (companion), Delete. Each row shows a live Connected / Not detected status.
4. **Next steps in Lightroom** button at the bottom.

## Import modal

Blocks the window; scrolling log; **Cancel** (enabled while running); **Done** (enabled only
once the process has finished). No "import all": cards and phones are swapped by hand.

## Status of the scaffold

Implemented: project generation, shared importer core, settings store, all views, card
importer, runner. Not yet verified with hardware: direct and companion phone imports from inside
the app (ImageCaptureCore callbacks need the main run loop, so direct import runs on the main
thread and the companion import on a worker thread), and the phone ready-check.

Planned next: inventory DB for cards, app icon, signing and notarization, a README section,
tests for `DestinationStore` and `CardImporter`.

## Building

```sh
brew install xcodegen
macos-app/generate.sh          # regenerates the importer core and PhotoImporter.xcodeproj
open macos-app/PhotoImporter.xcodeproj   # set DEVELOPMENT_TEAM in project.yml to sign
```
