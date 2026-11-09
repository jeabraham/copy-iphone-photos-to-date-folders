[Home](../README.md) · [Install the Mac app](../macos-app/INSTALL.md) · [Guide index](../README.md#guides)

# Memory cards and import history

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

For SQLite details, phone identity matching, and older imports, see [Inventory and duplicate handling](INVENTORY.md).
