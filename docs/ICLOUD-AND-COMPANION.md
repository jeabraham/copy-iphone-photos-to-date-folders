[Home](../README.md) · [Install the Mac app](../macos-app/INSTALL.md) · [Guide index](../README.md#guides)

# iCloud Photos and the iPhone companion

**USB access cannot force-download an iCloud-only original.** ImageCaptureCore
can copy only media that iOS exposes. Offloaded photos may be absent from the
catalog or fail to download; even a successful run does not prove the selected
iCloud date range was complete.

For people using **Optimize iPhone Storage**, downloading the entire library onto
the phone is usually not a practical workaround: the originals may exceed the
phone's available storage. Keep optimization enabled if you need it.

The companion app described below is intended for fetching selected offloaded
originals through PhotoKit and transferring them over USB. It is not yet publicly
available as an installable app; [contact the author for a copy](https://github.com/jeabraham/copy-iphone-photos-to-date-folders/issues/new).
It needs an internet connection for iCloud downloads and may still need temporary
space on the phone. Try a small date range first.

Alternatively, export originals through iCloud.com or a Mac Photos library that
has enough disk space to download them. Check the export against the expected
library contents; the USB catalog is not an authoritative cloud inventory.

**Only if your phone has enough space for the entire original library:** you can
choose **Download and Keep Originals** in its iCloud Photos settings, leave it on
Wi-Fi and power, and wait for downloads to finish before reconnecting. This is an
optional approach for sufficiently spacious phones, not the normal recommendation
for someone relying on optimized storage. **Keep Originals** under Transfer to
Mac or PC is a separate setting: it controls conversion, not iCloud downloads.

## Checking a selected date range

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

For a small range, you can try the following without downloading the whole library;
it does not guarantee that every original will become available through USB:
on Wi-Fi and power, open the needed photos in the iPhone Photos app and let any
"Downloading from iCloud" indicators finish before importing, import small
ranges at a time, and keep older ranges in a separate iCloud/Mac export.
Recent photos are usually the least affected.

Apple's [Image Capture guide](https://support.apple.com/guide/image-capture/transfer-images-imgcp1003/mac)
describes transferring media from connected devices.

## Companion app: availability and developer setup

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
rule, `--exclude-movies` and `--overwrite` follow the [shared inventory rules](INVENTORY.md),
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
