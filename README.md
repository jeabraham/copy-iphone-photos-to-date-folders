# Photo Copier - Date Folders

A small macOS app for copying photos and videos from memory cards and USB-connected
iPhones into ordinary `YYYY/YYYY-MM-DD` folders, ready to add to Lightroom Classic.
For example: `2026/2026-11-09/IMG_1234.HEIC`.

The app is intended to make repeat imports practical as a camera card fills up:
it remembers successful imports and skips recognized files **before reading their
photo contents again**. It still scans directory entries and file metadata.
It does not delete source photos or modify your Lightroom catalog.

**Early alpha — testers wanted.** Start with backed-up photos, a small date range,
and a separate test destination. Provided without warranty; this is an independent
project, not affiliated with Adobe or Apple.

- **Download:** [Mac app releases](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/releases).
  Choose an attached Mac app ZIP or DMG; GitHub's **Source code** downloads are not
  installable apps. If a release has no packaged app asset, build from source below.
- **Requirements:** macOS **15 or later** for the Mac app. Check the release notes
  for the supported Mac architectures and features included in that build.
- **Installation and first import:** [Installation guide](macos-app/INSTALL.md).
- **Feedback:** [Report a bug or request a feature](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new),
  or [browse existing issues](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues).

## Quick start with the Mac app

1. Download and unpack the app, drag **Photo Copier - Date Folders.app** to
   **Applications**, and open it.
2. Choose a destination folder. Keep its hidden `.iphone-import.sqlite3` database
   with your photos: it stores settings, saved sources, and import history.
3. Add a source with **+**:
   - **Memory card:** choose `DCIM` and name the card, for example **Egypt Card #1**.
   - **iPhone:** connect by USB, unlock it, tap **Trust**, and close competing import
     windows in Lightroom, Photos, and Image Capture. Use **Import directly**.
4. Select an optional From/To date range. Review Settings, leave **Overwrite** off
   for normal imports, and optionally preview with **Dry run** before copying.
5. Import, check the results, then use **Add** in Lightroom Classic's Import dialog
   to add the destination photos to your catalog. The app's **Next steps in Lightroom**
   explains this workflow.

Videos are off by default in the Mac app; each source can override the destination's
video, overwrite, and dry-run settings. The command-line iPhone script has different
defaults: it includes videos unless `--exclude-movies` is supplied.

## iPhone originals stored in iCloud

With **Optimize iPhone Storage**, direct USB imports may miss originals that have
been offloaded to iCloud. Downloading the entire library back onto the phone is
usually impractical for people who need optimized storage.

A very simple **Photo Import Companion** iPhone app handles selected offloaded
originals. It is **not yet publicly available as an installable app**;
[contact the author for a copy](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new).
Its source is included. See [iCloud and the companion app](docs/ICLOUD-AND-COMPANION.md)
for limitations, alternatives, and developer setup.

## Guides

- [Install and try the Mac app](macos-app/INSTALL.md)
- [Memory cards](docs/MEMORY-CARDS.md): naming, UUID markers, formatted cards, missing markers, and read-only fallback.
- [Inventory and duplicate handling](docs/INVENTORY.md): skipped files, overwrite, adoption, deleted photos, and database backups.
- [iCloud and the companion app](docs/ICLOUD-AND-COMPANION.md): offloaded originals and available workflows.
- [iPhone command-line importer](docs/IPHONE-CLI.md): commands, options, and connection troubleshooting.
- [SD-card shell command](docs/SD-CARD-CLI.md): the simpler copier without import history.
- [Build and test](docs/DEVELOPMENT.md): Xcode setup and regression tests.

The card guides describe the current source; check release notes for features
included in a downloaded build. Keep the hidden `.iphone-import.sqlite3` database
with your photos, and back it up too.

## Feedback and license

Please include the app version or download filename, macOS version, source device,
steps to reproduce, and expected versus actual results in a
[GitHub issue](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new).
Issues are public: redact personal paths, identifiers, and photo details from logs
and screenshots. Reports of confusing instructions are welcome too.

See [LICENSE](LICENSE) for the Apache License 2.0 terms and warranty disclaimer.
