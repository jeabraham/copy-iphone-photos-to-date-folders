#!/bin/bash

DEFAULT_SRC="/Volumes/NIKON Z 5  /DCIM/102NCZ_5"
SRC="$DEFAULT_SRC"
DEST="."
DRYRUN=false

print_help() {
  echo "Usage: $(basename "$0") [--src <path>] [--dry-run] [--help]"
  echo
  echo "Options:"
  echo "  --src <path>     Source directory (default: \"$DEFAULT_SRC\")"
  echo "  --dry-run        Show what would be copied, without changing anything"
  echo "  --help, -h       Show this help message"
  echo
  echo "Copies image files to the current directory in YYYY-MM-DD subfolders,"
  echo "using macOS filesystem creation dates. Existing files are not overwritten."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRYRUN=true ;;
    --src)
      if [[ "$#" -lt 2 || -z "$2" || "$2" == --* ]]; then
        echo "Missing path for --src" >&2
        exit 1
      fi
      SRC="$2"
      shift
      ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; print_help; exit 1 ;;
  esac
  shift
done

echo "Source: \"$SRC\""
echo "Destination: \"$DEST\""
echo "Dry run: $DRYRUN"

if [[ ! -d "$SRC" ]]; then
  echo "Source directory does not exist: \"$SRC\"" >&2
  exit 1
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo "This script requires macOS stat (filesystem creation dates)." >&2
  exit 1
fi

# Absolute paths also protect filenames starting with a dash from utility options.
SRC="$(cd "$SRC" && pwd)" || exit 1
while IFS= read -r -d '' file; do
  date=$(stat -f "%SB" -t "%Y-%m-%d" "$file" 2>/dev/null)
  if [[ -z "$date" ]]; then
    echo "Skipping (no creation date): $file"
    continue
  fi
  target_dir="$DEST/$date"
  filename=$(basename "$file")
  dest_file="$target_dir/$filename"

  if [[ -e "$dest_file" || -L "$dest_file" ]]; then
    echo "Skipping (already exists): $dest_file"
  elif [[ "$DRYRUN" == true ]]; then
    echo "[DRY RUN] Would copy: \"$file\" → \"$dest_file\""
  else
    mkdir -p "$target_dir" || exit 1
    cp -n "$file" "$dest_file" || exit 1
    echo "Copied: \"$file\" → \"$dest_file\""
  fi
done < <(find "$SRC" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.nef" -o -iname "*.cr2" -o -iname "*.dng" -o -iname "*.arw" -o -iname "*.heic" -o -iname "*.tif" -o -iname "*.tiff" \) -print0)
