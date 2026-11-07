# copy-iphone-photos-to-date-folders

Copy media from a USB-connected iPhone into ordinary date folders, without
first syncing to a Mac Photos library. Also includes an SD-card image copier.
Neither script deletes anything from its source.

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
size. Missing files are reimported. Changed/unreadable saved files are reported;
use `--overwrite` to refresh them. This is metadata-based deduplication, not
content hashing: same-size external changes are not detected, and changing source
names, catalog paths, creation dates, or transfer formats can result in new copies.
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
with its database. Do not manually move/rename individual files without updating
the inventory, or copies will be recreated at their recorded paths. The
`.iphone-import.lock` file may remain after a run; it is a lock handle, not a
database, and its presence alone does not mean an import is running.

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

## USB companion app (handles Optimize iPhone Storage)

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
and re-running resumes safely. Files that fail (for example, an iCloud download
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

This preserves the supplied memory-card workflow: images only, filesystem
creation dates, `YYYY/YYYY-MM-DD` folders in the **current directory**, and no overwrite.
It remains a standalone shell script and does not use the iPhone SQLite inventory.
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

There is no existing automated test/build infrastructure. Shell syntax and
lint can be checked with `bash -n copy-sd-photos.sh` and, if installed,
`shellcheck copy-sd-photos.sh`. On a Mac, run
`swiftc -typecheck copy-iphone-photos.swift`, then a dry run and a small real import
to verify device permissions, metadata, and transfer behavior. On non-macOS
hosts only option parsing and help are supported; actual imports require a Mac.
