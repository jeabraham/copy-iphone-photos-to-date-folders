[Home](../README.md) · [Install the Mac app](../macos-app/INSTALL.md) · [Guide index](../README.md#guides)

# SD-card shell command

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

For card identity and import history, use the [Mac app](../README.md) instead.
