#!/bin/bash
# Build the shared source in an isolated Swift Testing package; never touch a photo destination.
set -euo pipefail
cd "$(dirname "$0")/.."
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/photo-importer-tests.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Sources/ImporterCoreLibrary" "$package_dir/Tests/ImporterRegressionTests"
cp Tests/Package.swift "$package_dir/Package.swift"
Scripts/make-importer-core.sh ../copy-iphone-photos.swift "$package_dir/Sources/ImporterCoreLibrary/ImporterCore.swift"
cp PhotoImporter/Models.swift "$package_dir/Sources/ImporterCoreLibrary/Models.swift"
cp PhotoImporter/CardImporter.swift "$package_dir/Sources/ImporterCoreLibrary/CardImporter.swift"
cp Tests/*Tests.swift "$package_dir/Tests/ImporterRegressionTests/"
CLANG_MODULE_CACHE_PATH="$package_dir/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$package_dir/module-cache" \
swift test --disable-sandbox --cache-path "$package_dir/cache" --package-path "$package_dir"
