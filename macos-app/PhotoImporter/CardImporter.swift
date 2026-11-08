import Foundation

// Swift port of copy-sd-photos.sh (the script stays as the standalone tool), plus the app's
// date range, video and overwrite settings.
enum CardImporter {
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "dng", "arw", "heic", "tif", "tiff"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static func run(job: ImportJob, isCancelled: () -> Bool, log: (String) -> Void) -> Int32 {
        let options: Options
        do { options = try job.importerOptions() } catch {
            log(error.localizedDescription)
            return 1
        }
        let source = URL(fileURLWithPath: job.source.location, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            log("Source directory does not exist: \"\(source.path)\"")
            return 1
        }
        log("Source: \"\(source.path)\"")
        log("Destination: \"\(options.destination.path)\"")
        log("Dry run: \(options.dryRun)")

        var extensions = photoExtensions
        if !options.excludeMovies { extensions.formUnion(videoExtensions) }
        let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey]
        guard let walker = FileManager.default.enumerator(at: source, includingPropertiesForKeys: keys) else {
            log("Cannot read \(source.path)")
            return 1
        }

        var copied = 0, skipped = 0, failures = 0
        for case let file as URL in walker {
            if isCancelled() {
                log("Cancelled.")
                return 1
            }
            let name = file.lastPathComponent
            // Cards from some cameras carry AppleDouble "._" companions that are not photos.
            guard !name.hasPrefix("._"), extensions.contains(file.pathExtension.lowercased()),
                  let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            guard let date = values.creationDate else {
                log("Skipping (no creation date): \(file.path)")
                skipped += 1
                continue
            }
            guard options.includes(date) else { continue }
            do {
                let target = try options.target(name: name, date: date)
                let exists = FileManager.default.fileExists(atPath: target.path)
                    || (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil
                if exists && !options.overwrite {
                    log("Skipping (already exists): \(target.path)")
                    skipped += 1
                } else if options.dryRun {
                    log("[DRY RUN] Would \(exists ? "replace" : "copy"): \"\(file.path)\" → \"\(target.path)\"")
                } else {
                    try copy(file, to: target, replacing: exists)
                    log("\(exists ? "Replaced" : "Copied"): \"\(file.path)\" → \"\(target.path)\"")
                    copied += 1
                }
            } catch {
                log("Failed \(name): \(error.localizedDescription)")
                failures += 1
            }
        }
        log("Copied: \(copied); skipped: \(skipped); errors: \(failures)")
        return failures == 0 ? 0 : 1
    }

    // Copies next to the target first so an interrupted copy never leaves a partial photo in place.
    private static func copy(_ file: URL, to target: URL, replacing: Bool) throws {
        let manager = FileManager.default
        let directory = target.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(".card-import-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: partial) }
        try manager.copyItem(at: file, to: partial)
        if replacing {
            guard rename(partial.path, target.path) == 0 else {
                throw ImportError(message: "Cannot replace \(target.path): \(String(cString: strerror(errno)))")
            }
        } else {
            try manager.moveItem(at: partial, to: target)
        }
    }
}
