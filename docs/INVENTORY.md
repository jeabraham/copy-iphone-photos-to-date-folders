[Home](../README.md) · [Install the Mac app](../macos-app/INSTALL.md) · [Guide index](../README.md#guides)

# Inventory and duplicate handling

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


See also [Memory cards](MEMORY-CARDS.md) and [iPhone command-line usage](IPHONE-CLI.md).
