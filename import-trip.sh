#!/bin/bash
# End-of-day guided import: camera card, then each iPhone, into YYYY/YYYY-MM-DD folders.
# Copy this script into a trip folder and run it there; nothing is deleted from any source.

DIR="${COPY_PHOTOS_TOOLS:-$(cd "$(dirname "$0")" && pwd)}"
DEST="."
FROM=""
TO=""
SD_SRC="/Volumes/NIKON Z 5  /DCIM/102NCZ_5"
PHONES="iPhone 1,iPhone 2"
DRYRUN=false

print_help() {
  echo "Usage: $(basename "$0") [--dest <dir>] [--tools <dir>] [--from YYYY-MM-DD] [--to YYYY-MM-DD]"
  echo "                        [--phones \"Name 1,Name 2\"] [--sd-src <path>] [--dry-run]"
  echo
  echo "  --dest    Destination root (default: current directory)"
  echo "  --tools   Folder with copy-iphone-photos.swift and copy-sd-photos.sh"
  echo "            (default: \$COPY_PHOTOS_TOOLS, else this script's folder)"
  echo "  --phones  Comma-separated phone names, in the order to import them"
  echo "  --sd-src  Camera card folder (default: the Nikon Z 5 card)"
  echo
  echo "Walks you through the camera card and each phone. Safe to rerun:"
  echo "files that were already imported are skipped."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRYRUN=true ;;
    --dest|--tools|--from|--to|--phones|--sd-src)
      if [[ "$#" -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "Missing value for $1" >&2; exit 1
      fi
      case "$1" in
        --dest) DEST="$2" ;;
        --tools) DIR="$2" ;;
        --from) FROM="$2" ;;
        --to) TO="$2" ;;
        --phones) PHONES="$2" ;;
        --sd-src) SD_SRC="$2" ;;
      esac
      shift
      ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; print_help; exit 1 ;;
  esac
  shift
done

if [[ ! -f "$DIR/copy-iphone-photos.swift" || ! -x "$DIR/copy-sd-photos.sh" ]]; then
  echo "Cannot find the import tools in \"$DIR\"." >&2
  echo "Pass --tools <path to copy-iphone-photos-to-date-folders> or set COPY_PHOTOS_TOOLS." >&2
  exit 1
fi
DIR="$(cd "$DIR" && pwd)"
mkdir -p "$DEST" || exit 1
DEST="$(cd "$DEST" && pwd)"

# Asks what to do after a problem; returns 0 to retry, 1 to skip this device.
retry_or_skip() {
  local answer
  while true; do
    read -r -p "Press Enter to try again, or type s to skip this step: " answer || exit 1
    case "$answer" in
      "") return 0 ;;
      s|S) return 1 ;;
    esac
  done
}

import_camera() {
  local args=(--src "$SD_SRC")
  [[ "$DRYRUN" == true ]] && args+=(--dry-run)
  echo
  echo "=== STEP 1: Camera card ==="
  while true; do
    read -r -p "Put the camera card in the Mac, then press Enter (s to skip): " answer || exit 1
    [[ "$answer" == s || "$answer" == S ]] && return
    if [[ ! -d "$SD_SRC" ]]; then
      echo "The card was not found at: $SD_SRC"
      echo "Check that it is fully inserted and appears in Finder."
      echo "If the card shows under a different name, rerun with --sd-src <folder>."
      retry_or_skip && continue || return
    fi
    # copy-sd-photos.sh writes to the current directory.
    if (cd "$DEST" && "$DIR/copy-sd-photos.sh" "${args[@]}"); then
      echo "Camera card done. You can eject it now."
      return
    fi
    echo "The camera copy reported a problem (see messages above)."
    retry_or_skip || return
  done
}

import_phone() {
  local step="$1" name="$2"
  local args=(--dest "$DEST" --exclude-movies --adopt-existing --companion)
  [[ -n "$FROM" ]] && args+=(--from "$FROM")
  [[ -n "$TO" ]] && args+=(--to "$TO")
  [[ "$DRYRUN" == true ]] && args+=(--dry-run)
  echo
  echo "=== STEP $step: $name ==="
  echo "  1. Unplug any other phone or camera from the Mac."
  echo "  2. Plug in $name with its USB cable and unlock it (tap Trust if asked)."
  echo "  3. On $name, open the Photo Import Companion app and leave it open."
  while true; do
    read -r -p "Press Enter when $name is ready (s to skip): " answer || exit 1
    [[ "$answer" == s || "$answer" == S ]] && return
    if swift "$DIR/copy-iphone-photos.swift" "${args[@]}"; then
      echo "$name done. You can unplug it now."
      return
    fi
    echo
    echo "That did not finish cleanly. Most common causes:"
    echo "  - The companion app is not open and in front on the phone."
    echo "  - The phone is locked, or you have not tapped Trust."
    echo "  - Another phone is still plugged in."
    echo "  - Lightroom Classic, Image Capture or Photos opened an import window for the"
    echo "    phone and grabbed the cable. Close that window (or quit the app), then retry."
    echo "  - The phone has not allowed Full Access to Photos."
    echo "  - A photo is still downloading from iCloud: stay on Wi-Fi and retry."
    retry_or_skip || return
  done
}

echo "Importing into: $DEST"
import_camera
step=2
IFS=',' read -r -a phone_list <<< "$PHONES"
for phone in "${phone_list[@]}"; do
  import_phone "$step" "$(echo "$phone" | sed 's/^ *//; s/ *$//')"
  step=$((step + 1))
done

cat <<EOF

=== ALL DONE ===
Now in Lightroom Classic:
  1. File > Import Photos and Video...
  2. Under Source, choose this folder:
       $DEST
  3. Tick "Include Subfolders" and choose "Add" at the top (do not Copy or Move).
  4. Tick "Don't Import Suspected Duplicates", then click Import.
EOF
