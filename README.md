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

Existing destination files with the same filename and date folder are skipped
**before downloading**, with no metadata database needed. This also recognizes
files imported by another tool into the same layout. It is not content-based
deduplication: two different assets/devices with the same date and filename
collide, and changing filenames/dates can result in another copy. Use separate
destinations for different phones when necessary. Existing partial files from
other tools are also skipped; use `--overwrite` to repair them.

`--overwrite` replaces every matching destination in the selected range, not
just edited files. Edit detection is not automatic, and only the rendition
exposed by iOS is copied; not every Photos edit is necessarily exposed over USB.
Downloads are staged in the destination filesystem and successful overwrites
are atomic. A failed transfer does not replace an existing photo. Dry runs
still connect and enumerate the phone but do not create directories or download.

If multiple cameras/phones are connected, use `--device "Exact iPhone Name"` to
select one; otherwise the first discovered camera is used. Discovery, catalog
enumeration, and stalled transfers time out after 120 idle seconds. Increase
`--timeout 600` for a large library or slow phone. Errors produce a nonzero exit
status; check the final copied/skipped/error counts and messages.

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

If the originals cannot fit on the phone, use a separate iCloud export workflow
(for example, iCloud.com downloads or a Mac Photos library with originals
downloaded, followed by Photos Takeout). Compare against the expected library
contents; do not treat the USB catalog as an authoritative cloud inventory.
Apple's [Image Capture guide](https://support.apple.com/guide/image-capture/transfer-images-imgcp1003/mac)
describes transferring media from connected devices.

## SD-card copier (macOS)

This preserves the supplied memory-card workflow: images only, filesystem
creation dates, `YYYY-MM-DD` folders in the **current directory**, and no overwrite.
Its default source is `/Volumes/NIKON Z 5  /DCIM/102NCZ_5`.

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
