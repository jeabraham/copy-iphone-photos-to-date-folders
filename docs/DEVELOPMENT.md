[Home](../README.md) · [Install the Mac app](../macos-app/INSTALL.md) · [Guide index](../README.md#guides)

# Build and test

With Xcode and XcodeGen installed, run from the repository directory:

```sh
bash macos-app/generate.sh
open macos-app/PhotoImporter.xcodeproj
```

Select the **PhotoImporter** scheme and build/run it. Configure your own signing
team as needed. The Xcode project is generated from `macos-app/project.yml`; keep
persistent build-setting changes there. Building locally does not itself submit
the app for notarization. The shared importer is generated from
`copy-iphone-photos.swift`; edit that source rather than its generated copy.

## Validation

Run the Swift Testing regression suite with `bash macos-app/Tests/run.sh`.
It exercises the shared inventory and macOS card importer in temporary directories.
Shell syntax and lint can be checked with `bash -n copy-sd-photos.sh` and, if installed,
`shellcheck copy-sd-photos.sh`. On a Mac, run
`swiftc -typecheck copy-iphone-photos.swift`, then a dry run and a small real import
to verify device permissions, metadata, and transfer behavior. On non-macOS
hosts only option parsing and help are supported; actual imports require a Mac.
