# Install Photo Copier - Date Folders (Mac beta)

Photo Copier - Date Folders copies photos from memory cards and iPhones into `YYYY/YYYY-MM-DD` folders, ready to add to a Lightroom Classic catalog. This is an independent project, not affiliated with Adobe.

## Requirements

- macOS 15 (Sequoia) or later.
- A Mac supported by the architecture listed in the release notes (Apple silicon, Intel, or Universal).
- A memory card/card reader or an iPhone connected by USB.
- Enough free space at your chosen destination for the copied photos and videos.

Lightroom Classic is used after copying; it does not need to be running during an import. Use **Import directly** for photos stored on the phone.

The optional **Import via app** mode requires **Photo Import Companion**, a very simple iPhone app that is **not yet publicly available**. It is currently only useful for photos whose originals have already been offloaded from the phone by iCloud Photos. If you would like a copy, [contact the author on GitHub](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new). If you have the companion, keep it open on the phone and allow Full Access to Photos there.

## Download and install

1. Open the [GitHub Releases page](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/releases) and choose a Mac beta release. Read its known issues and compatibility notes.
2. Under **Assets**, download the packaged Mac app (`.zip` or `.dmg`). The automatically generated **Source code** downloads are not installable apps. If no Mac app asset is listed, a packaged beta is not available yet.
3. For a ZIP, double-click to extract it. For a DMG, double-click to open it.
4. Drag **Photo Copier - Date Folders.app** into **Applications**. If replacing an earlier version, quit it first.
5. Open the app from **Applications**. If macOS asks whether to open an app downloaded from the internet, confirm that it is the download you selected.
6. Allow access to the selected folders, removable volumes, or connected device when prompted for your import workflow.

Public beta downloads should be Developer ID signed and notarized. If macOS says it cannot verify the developer, cannot check the app for malicious software, or that the app is damaged, stop and [report the exact message](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new). Include the release version and download filename.

## Try your first import

1. Start with backed-up photos and a new, empty destination folder for beta testing.
2. Choose that folder as the import destination. The app stores its settings and import history in a hidden database inside the destination.
3. Add a source with **+**:
   - **Memory card:** select the card's `DCIM` folder.
   - **iPhone:** connect by USB, unlock the phone, tap **Trust** if asked, and close the import windows in Lightroom, Photos, and Image Capture. Connect only one phone or camera at a time.
4. Choose a small date range for the first test. Leave **Overwrite** off. Optionally enable **Dry run** in Settings to preview the import, then disable it to copy files.
5. Press **Import** and wait for completion. Open several copied photos or videos to check them.
6. Run the same import again and check that previously imported files are skipped.
7. Use **Next steps in Lightroom** to add the destination folder to your Lightroom Classic catalog.

If an iPhone original is still downloading from iCloud, keep the phone on Wi-Fi and try again when it is available.

## Send feedback

- [Report a bug or suggest an improvement](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new)
- [Browse existing reports](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues)

Sign in to GitHub to submit a report. Search existing issues first, then include:

```text
App version / downloaded filename:
macOS version:
Mac model / Apple silicon or Intel:
Source: memory card / iPhone direct / iPhone companion
Phone or camera model (if relevant):
Destination: internal disk / external disk / network volume

Steps to reproduce:
1.
2.

Expected result:
Actual result:
Error message (if any):
```

Screenshots or a short log excerpt help. GitHub issues are public: remove personal file paths, device identifiers, and private photo information before posting.

## Update or uninstall

To update, quit the app and replace it in Applications with the newer download. To uninstall, quit the app and move it from Applications to the Trash. Copied photos and the destination's hidden settings/history database remain in the destination folder.

## Memory-card identity

When adding a card or creating a new identity after formatting, choose a recognizable name such as **Egypt Card #1**. Consider writing that name on the physical card too. Use a distinct name for a new use of a formatted card. You can change an existing row’s name in **Settings → Name** without changing its UUID or import history.

The app writes a small, visible `PhotoImporter-Card-ID.txt` containing a UUID one level above the selected folder (normally beside `DCIM`). It reads that identifier before importing; the volume name and mount path are not the card's identity. Do not copy the identifier onto another card.

When upgrading an existing unmarked row, confirm **Same Card** to preserve its import history, or **New Card** if the card was formatted or replaced. If an expected marker disappears, choose **Same Card — Retain History** only after accidental deletion on the same, unformatted card. This restores the saved UUID and retains import history. If restoration fails, you can continue without the marker for that import; the saved UUID is retained and you must confirm again next time. Choose **New Card** after formatting or replacing a card. A different marker also offers a separate identity. Creating a new row is followed by a choice to mark the old location obsolete. Obsolete rows keep their history but cannot import until reactivated with **Update location**. A recognized card can reuse its existing row even at a different location.

If a marker cannot be written, you can cancel or continue without it. Unmarked cards require identity confirmation each time; choose **New Card** after formatting or replacing one. Invalid or unreadable existing marker files stop the operation rather than being overwritten.

Choosing a folder other than `DCIM` displays a warning with **Choose Another Folder**, **Use This Folder**, and **Cancel** options. Identity setup may write the marker even when the photo import is configured as a dry run; the photo dry run still copies no photos.
