[Home](../README.md) · [Install the Mac app](../macos-app/INSTALL.md) · [Guide index](../README.md#guides)

# iPhone command-line importer (macOS 11 or later)

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

See [Inventory and duplicate handling](INVENTORY.md) for adoption, overwrite, and SQLite behavior, and [iCloud and the companion app](ICLOUD-AND-COMPANION.md) for offloaded originals.
