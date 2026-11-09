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

### iPhone and iCloud limitations

Direct USB importing can copy only media the phone exposes. With **Optimize iPhone
Storage**, some originals may have been offloaded to iCloud; a successful direct
import does not establish that every photo in the date range was available.

**Photo Import Companion** is a very simple iPhone app whose current purpose is to
handle those offloaded originals. It is **not yet publicly available as an installable
app**. [Contact the author for a copy](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new).
Its source is included in `ios-companion/` for developers who want to build it.
If you have it installed, use **Import via app**, leave it open on the phone, grant
Full Access to Photos, and keep the phone online for iCloud downloads. It exports
original resources, not edited renditions. See the companion section below.

### Memory-card identity and repeat imports

Give each card a recognizable name, such as **Egypt Card #1**, and consider writing
that name on the physical card. **Settings → Name** changes the label without
changing its identity or import history.

The app creates a small, visible **`PhotoImporter-Card-ID.txt`** containing a UUID
one level above the selected folder, normally beside `DCIM`. That UUID identifies
the card independently of its volume name, mount path, or saved row. Do not copy
the marker to another card. Use **Update location** when the card moves; recognized
cards can reuse their saved row and history.

- **Accidentally deleted marker, same unformatted card:** choose **Same Card —
  Retain History**. The app restores the saved UUID if possible and keeps the history.
- **Formatted or replacement card:** choose **New Card**, give it a recognizable
  name, and optionally mark the old location **obsolete**. The old history remains;
  an obsolete row cannot import until reactivated with **Update location**.
- **A different marker:** the app offers the recognized card's row if known, or a
  new row. It does not overwrite another card's marker.
- **Read-only card or marker write failure:** cancel or continue without a marker.
  Identity must be confirmed again on the next import. If this was a previously
  marked card, its historical UUID is retained even when restoration fails.
- **Unreadable or invalid existing marker:** the operation stops with an error;
  the file is not silently overwritten.

Existing rows created before this feature ask **Same Card** or **New Card** when
first checked. Choose Same Card only if the card has not been formatted or replaced.
Choosing a folder other than `DCIM` produces a warning and an option to return to
the folder picker. Keep the same source folder level: file identities also include
the relative path and filesystem creation timestamp.

Normal repeat card imports check the inventory and destination file metadata without
copying or comparing RAW contents again. A new source identity may require a full
copy before identical-content matching within that same card identity. Creating a
new card identity can produce additional copies of previously imported photos.

**Adopt matching files already in the destination** is enabled by default in the
Mac app. It trusts matching names, date folders, and byte sizes for **untracked**
files. It does not compare contents, and it does not adopt files already assigned
to another card or phone. Turn it off if the origin of existing untracked files is
uncertain. It cannot recover history for photos deleted before inventory tracking.

**Redownload deleted photos** is off by default. Recognized photos you delete from
the destination stay deleted unless you enable it. **Overwrite** refreshes existing
recorded files; it does not automatically detect source edits. Interrupted imports
retry their transfer. Back up the database along with your photos.

A photo **Dry run** copies no photos. Card setup or identity recovery can still write
the marker, and source settings can still be saved. The app never deletes photos
from the card.

## Build the Mac app from source

With Xcode and XcodeGen installed, run from the repository directory:

```sh
bash macos-app/generate.sh
open macos-app/PhotoImporter.xcodeproj
```

Select the **PhotoImporter** scheme and build/run it. Configure your own signing
team as needed. The Xcode project is generated from `macos-app/project.yml`; keep
persistent build-setting changes there. Building locally does not itself submit
the app for notarization. The shared importer is generated from
`copy-iphone-photos.swift`; edit that source rather than its generated copy.

## Command-line tools

The repository also retains the iPhone Swift importer and a deliberately simplified
SD-card shell copier. The following sections document their behavior and options.

## iPhone importer (macOS 11 or later)

Requires Apple's command-line developer tools (`xcode-select --install`), which
provide Swift. No third-party packages, Lightroom, or Photos library are required.
The script uses macOS ImageCaptureCore, the framework behind Image Capture.

1. Connect the iPhone with a data-capable USB cable.
2. Unlock it, accept **Trust This Computer**, and keep it unlocked during import.
3. If macOS prompts for access to photos or removable devices, grant access to
   the terminal/tool running the script. Close other apps importing from the phone.
4. For original HEIC/HEVC files, choose **Keep Originals** under the iPhone's
   Photos settings → Transfer to Mac or PC (under Settings → Apps → Photos on
   newer iOS). Automatic conversion can change filenames, types, or sizes.

From the repository directory:

```sh
# Preview an inclusive date range, excluding videos.
swift copy-iphone-photos.swift --dest "/Volumes/Photo Archive" \
  --from 2026-10-01 --to 2026-10-31 --exclude-movies --dry-run

# Copy the selected photos.
swift copy-iphone-photos.swift --dest "/Volumes/Photo Archive" \
  --from 2026-10-01 --to 2026-10-31 --exclude-movies

# Explicitly refresh existing files after editing on the iPhone.
swift copy-iphone-photos.swift --dest "/Volumes/Photo Archive" \
  --from 2026-10-01 --to 2026-10-01 --overwrite

swift copy-iphone-photos.swift --help
```

Files are stored as `DEST/2026/2026-10-01/IMG_1234.HEIC`. Dates use the device's
EXIF creation date when available, otherwise its item/file creation date,
interpreted in the Mac's local time zone. Undated files are reported and skipped.
Either date bound can be omitted; omitting both selects all exposed media.
Videos are included by default. `--exclude-movies` also excludes Live Photo video
companions; it keeps their still images. Non-image/video sidecars such as `.AAE`
are not exported, so this is a media copy, not a restorable Photos-library backup.

### Shared folders and the local inventory

Use the **same `--dest` for every phone**. The importer stores devices, original
filenames, source paths, creation/modification dates, source sizes, and saved paths
in `DEST/.iphone-import.sqlite3`, using macOS's built-in SQLite library.
Device identity uses the serial number exposed by ImageCaptureCore, not the
phone's display name or a session-specific PTP handle. If no serial is available,
the importer asks for `--device-id`; supply a unique, permanent label and reuse it
on every import from that phone. An explicit label overrides the serial, so
switching identity schemes later causes the phone to be treated as a new device.
Renaming a phone does not change its serial-based identity.

A source file is identified by its device, full catalog path, and full creation
timestamp, not just its filename and day. A successful recorded import is skipped
**before downloading** if its saved file still exists with the recorded byte
size. Successfully imported files that you delete locally stay deleted by default,
even with `--overwrite`. Use `--redownload-deleted-files` (or **Redownload deleted
photos** in the macOS destination settings) to restore them. Failed or
interrupted imports still retry. Changed/unreadable saved files are reported;
use `--overwrite` to refresh them. This initial check uses metadata, so same-size
external changes are not detected.

For new source identities, a completed download is compared byte-for-byte with
previously imported files of the same name and size from the same phone. Identical
content is stored once, with both source identities recorded as aliases. This
handles duplicate DCIM entries and switching between direct and companion imports.
Different phones retain separate copies; different bytes are never merged. Existing
duplicate files are not removed. Overwrite bypasses this content matching.
The first encounter still transfers the bytes to verify them; dry runs cannot
predict this reduction because they do not download media.
Duplicate indistinguishable catalog entries are reported rather than silently merged.

The first asset normally keeps `IMG_1234.HEIC`. A different asset or phone whose
name clashes gets `IMG_1234__<device-token>.HEIC`, with an additional number if
needed. All files still share the same `YYYY/YYYY-MM-DD` folders. The inventory
remembers that assigned path so subsequent imports skip or overwrite the correct
file. Names already reserved in the inventory are not reused for another asset,
even when the file has been removed. Never delete the inventory merely to resolve
a collision.

`--overwrite` refreshes recorded assets belonging to the connected device in the
selected range, not another phone's files or untracked files. It refreshes all
selected recorded assets, not just edited ones. Edit detection is not automatic,
and only the rendition exposed by iOS is copied; not every Photos edit is
necessarily exposed over USB.
Downloads are staged in the destination filesystem and successful overwrites
are atomic. A failed transfer does not replace an existing photo. The inventory
reserves the path before transfer and marks success only after the file is saved.
An interrupted transfer is retried; a file left behind before success was recorded
is preserved and a new collision-safe name is chosen. A lock prevents two real
imports from using the same inventory concurrently.

Dry runs still connect and enumerate the phone, but read the inventory without
creating directories, database/lock files, or downloading media. New assignments
are only simulated; another import between preview and copying can change them.

**Back up the hidden `.iphone-import.sqlite3` file with your photos.** The
inventory contains device identifiers and photo metadata; treat it as private.
Paths are stored relative to `--dest`, so the entire destination can be moved
with its database. Moving/renaming individual files is treated as a local deletion
at the original path; the inventory does not track their new location. The
`.iphone-import.lock` file may remain after a run; it is a lock handle, not a
database, and its presence alone does not mean an import is running.

Real imports upgrade older inventories to schema version 2 to store aliases;
use the updated script and app with that destination. Dry runs also support
version 1 without modifying it.

The macOS app logs every import message, including file paths, to Console with
subsystem `com.jeabraham.PhotoImporter` and category `Import`. Messages include
an import session ID and remain available after closing the import window, subject
to macOS log retention. For example:

```bash
log show --last 1h --style compact --predicate 'subsystem == "com.jeabraham.PhotoImporter" AND category == "Import"'
```

Run the importer regression checks with `bash macos-app/Tests/run.sh`.

### Files imported before the inventory existed

Untracked files are preserved, even with `--overwrite`; the importer cannot
infer which phone they came from. By default it imports to collision-safe names,
which may create a one-time duplicate of an older import.

To register old copies **only when you know they belong to the connected phone**,
use `--adopt-existing`. This trusts filename, date folder, and byte-size matches;
it does not compare content and could attribute another phone's photo incorrectly.
It refuses adoption when the existing file's size differs or it is not a regular
file. Adoption and overwrite must be run separately.

```sh
# Connect the phone whose photos were previously copied into this destination.
# Verify the preview against the known old imports before removing --dry-run.
swift copy-iphone-photos.swift --dest "/Volumes/Photo Archive" \
  --from 2026-11-06 --exclude-movies --adopt-existing --dry-run

# Both phones can then import to the same root, without a per-phone subfolder.
swift copy-iphone-photos.swift --dest "/Volumes/Photo Archive" \
  --from 2026-11-06 --exclude-movies
```

Files under an old per-phone subfolder are not automatically migrated. Preserve
them until you have verified the new shared-root import and its inventory.

If multiple cameras/phones are connected, use `--device "Exact iPhone Name"` to
select one; otherwise the first discovered camera is used. Discovery, catalog
enumeration, and stalled transfers time out after 120 idle seconds. Increase
`--timeout 600` for a large library or slow phone. Errors produce a nonzero exit
status; check the final copied/skipped/error counts and messages.

### “Please unlock” even though the phone is unlocked

ImageCaptureCore can report restricted media access independently of the screen's
visible lock state. Image Capture working does not establish that this script's
session can access the phone. The importer retries only the framework's
passcode-locked/access-restricted session error every two seconds, for at most
`--timeout` seconds. It also retries when the framework reports restrictions
removed. Other session errors still fail immediately, with their domain and code.
It does not bypass trust or permissions, and this recovery is not a verified fix
for any particular macOS/iOS release.

Quit Image Capture, Photos, Lightroom, and other importing apps; reconnect the
phone while unlocked and keep it awake. Accept any access prompts for the
terminal/tool running the script, and review its available permissions in
System Settings → Privacy & Security. If it still fails, include the reported
error domain/code and whether Image Capture can list photos after a reconnect.
Increasing `--timeout` gives access recovery more time, but cannot grant access.

Inside a quoted destination path, spaces must **not** be escaped with backslashes:
use `--dest "/Volumes/Photo Archive/My Photos"`, not
`--dest "/Volumes/Photo\ Archive/My\ Photos"`.

### iCloud / optimized storage limitation

**USB access cannot force-download an iCloud-only original.** ImageCaptureCore
can copy only media that iOS exposes. Offloaded photos may be absent from the
catalog or fail to download; even a successful run does not prove the selected
iCloud date range was complete.

Before importing, choose **Download and Keep Originals** in the iPhone's
Photos/iCloud Photos settings. Leave the phone on Wi-Fi and power, with enough
free storage, and allow the original downloads to finish. Then reconnect and
run the importer again. This phone-side download does not require syncing photos
to the Mac; the script itself cannot automate or verify it. **Keep Originals**
under Transfer to Mac or PC controls conversion, not iCloud downloading.

#### Diagnosing offloaded photos without downloading everything

With **Optimize iPhone Storage** on, iOS keeps full-resolution originals for
recent or frequently viewed photos and may keep only smaller device copies of
older ones. Image Capture (and this script) can still *list* many older items,
so being listed does not prove the original is on the phone. This behavior is
based on observation, not an Apple guarantee; treat it as unverified for your
iOS version. To check a date range:

1. Run with `--dry-run` for the range and note the item count.
2. Compare it with the iPhone Photos app (or iCloud.com) count for the same
   range. Missing items suggest they were not exposed over USB.
3. After a real run, spot-check imported files: unexpectedly small file sizes
   or dimensions, download errors, or timeouts point to non-original copies or
   failed iCloud fetches. Check Settings → Photos for **Optimize iPhone Storage**
   and Settings → General → iPhone Storage → Photos for how much is offloaded.
4. Re-run after fixing the cause; the inventory prevents re-copying recorded files.

To avoid problems without keeping all of history on the phone, work by range:
on Wi-Fi and power, open the needed photos in the iPhone Photos app and let any
"Downloading from iCloud" indicators finish before importing, import small
ranges at a time, and keep older ranges in a separate iCloud/Mac export.
Recent photos are usually the least affected.

If the originals cannot fit on the phone, use a separate iCloud export workflow
(for example, iCloud.com downloads or a Mac Photos library with originals
downloaded, followed by Photos Takeout). Compare against the expected library
contents; do not treat the USB catalog as an authoritative cloud inventory.
Apple's [Image Capture guide](https://support.apple.com/guide/image-capture/transfer-images-imgcp1003/mac)
describes transferring media from connected devices.

## USB companion app (limited availability)

The companion is not yet publicly available as an installable app. It is a very
simple app, currently useful for originals offloaded by iCloud Photos.
[Contact the author if you would like a copy](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new).
The following instructions are for building it yourself.

`ios-companion/` contains a small SwiftUI app that uses PhotoKit to fetch
originals, **including iCloud-offloaded ones**, and stream them to the Mac over
the USB cable. No Wi-Fi share is needed. The Mac script reaches the app through
`usbmuxd` (the same channel Xcode uses); the app listens on the phone's loopback
interface only (port 58214), so it is not reachable from the network.

1. Open `ios-companion/PhotoImportCompanion.xcodeproj` in Xcode, set your Team
   and a unique bundle identifier under Signing & Capabilities, and run it on the
   iPhone.
2. Allow **Full Access** to Photos. Keep the app open in the foreground and the
   phone unlocked, on Wi-Fi and power (iCloud downloads need a network).
3. Connect the phone by USB, trust the Mac, then run:

```sh
swift copy-iphone-photos.swift --companion --dest "/Volumes/Photo Archive" \
  --from 2026-10-01 --to 2026-10-31 --dry-run
```

Drop `--dry-run` to copy. The destination layout, SQLite inventory, no-overwrite
rule, `--exclude-movies` and `--overwrite` behave as in the Image Capture mode,
and re-running skips completed recorded imports and retries incomplete transfers. Files that fail (for example, an iCloud download
error) are reported and retried on the next run. Only original resources are
copied (photo, video, RAW alternate, Live Photo video), not edited renders, and
`--adopt-existing` works by matching filename, date and byte size against files
already in the destination (e.g. from an earlier Image Capture import).

**Other apps can grab the phone.** Lightroom Classic (its import dialog),
Photos, Image Capture and similar apps claim the phone when it is plugged in and
can block both the importer and Xcode installs (for example CoreDevice error
4016, "not able to fulfill the requested usage assertion requirements"). Quit
them, or disable their "open when a device is connected" behavior, then replug.

Limitations of this first version: one phone at a time, no on-screen progress
beyond a log, and no extra authentication beyond loopback-only access. Test with
a small date range first.

## SD-card copier (macOS)

### Recommended: Photo Copier - Date Folders

Use the Mac app for card naming, UUID markers, import history, collision handling,
and control over restoring deleted destination photos. See
[Memory-card identity and repeat imports](#memory-card-identity-and-repeat-imports)
above. These features are not provided by the shell command.

### Deliberately simplified shell command

Prefer **Photo Copier - Date Folders** for normal imports. The shell command
preserves the supplied memory-card workflow: images only, filesystem
creation dates, `YYYY/YYYY-MM-DD` folders in the **current directory**, and no overwrite.
It deliberately does not use an inventory, distinguish same-name photos from
different cards, or remember deleted imports. Deleted destination files will be
copied again. Both `-h`/`--help` and invocation without parameters display the
usage guide and app recommendation; no-argument invocation does not copy files.
Its default source is `/Volumes/NIKON Z 5  /DCIM/102NCZ_5`.

Existing files are skipped by filename within the target date folder. Previously
imported top-level `YYYY-MM-DD` folders are not moved, renamed, or deleted. Because
those legacy folders are not checked, importing the same card again may create
another copy under the new year/date layout.

```sh
# Run from the desired destination directory, using the script's actual path.
/path/to/repository/copy-sd-photos.sh --src "/Volumes/My Card/DCIM" --dry-run
/path/to/repository/copy-sd-photos.sh --src "/Volumes/My Card/DCIM"
```

Supported extensions: JPG, JPEG, NEF, CR2, DNG, ARW, HEIC, TIF, TIFF (case-insensitive).
Dry runs do not create directories.

## Validation

Run the Swift Testing regression suite with `bash macos-app/Tests/run.sh`.
It exercises the shared inventory and macOS card importer in temporary directories.
Shell syntax and lint can be checked with `bash -n copy-sd-photos.sh` and, if installed,
`shellcheck copy-sd-photos.sh`. On a Mac, run
`swiftc -typecheck copy-iphone-photos.swift`, then a dry run and a small real import
to verify device permissions, metadata, and transfer behavior. On non-macOS
hosts only option parsing and help are supported; actual imports require a Mac.

## Feedback and license

Please include the app version or download filename, macOS version, source device,
steps to reproduce, and expected versus actual results in a
[GitHub issue](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new).
Issues are public: redact personal paths, identifiers, and photo details from logs
and screenshots. Reports of confusing instructions are welcome too.

See [LICENSE](LICENSE) for the Apache License 2.0 terms and warranty disclaimer.
