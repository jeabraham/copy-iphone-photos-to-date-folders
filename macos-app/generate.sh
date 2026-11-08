#!/bin/bash
# Regenerates the importer core and the Xcode project (requires: brew install xcodegen).
set -euo pipefail
cd "$(dirname "$0")"
Scripts/make-importer-core.sh ../copy-iphone-photos.swift PhotoImporter/Generated/ImporterCore.swift
xcodegen generate
