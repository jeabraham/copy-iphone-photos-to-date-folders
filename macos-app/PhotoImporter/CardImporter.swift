import Foundation

// The app uses the shared inventory; copy-sd-photos.sh remains a simple standalone copier.
enum CardImporter {
    static let photoExtensions: Set<String> = ["jpg", "jpeg", "nef", "cr2", "dng", "arw", "heic", "tif", "tiff"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static func run(job: ImportJob, isCancelled: () -> Bool, log: @escaping (String) -> Void) -> Int32 {
        let options: Options
        do { options = try job.importerOptions() } catch {
            log(error.localizedDescription)
            return 1
        }
        let manager = FileManager.default
        let source = URL(fileURLWithPath: job.source.location, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            log("Source directory does not exist: \"\(source.path)\"")
            return 1
        }
        let sourceRoot = source.resolvingSymlinksInPath().path
        let destinationRoot = options.destination.resolvingSymlinksInPath().path
        guard sourceRoot != "/", destinationRoot != sourceRoot, !destinationRoot.hasPrefix(sourceRoot + "/") else {
            log("Choose a destination outside the card's source folder.")
            return 1
        }
        log("Source: \"\(source.path)\"")
        log("Destination: \"\(options.destination.path)\"")
        log("Dry run: \(options.dryRun)")

        // The on-card UUID owns import history independently of the row or mount path.
        // Unmarked cards use the row ID only after the UI asks the user to confirm identity.
        let identity = "card:\(job.source.cardUUID ?? job.source.id)"
        if job.source.obsolete == true {
            log("This card location is obsolete. Use Update location before importing.")
            return 1
        }
        if let expected = job.source.cardUUID {
            do {
                let actual = try CardIdentity.read(from: source)
                guard actual == expected || (actual == nil && job.allowMissingCardMarker) else {
                    throw ImportError(message: "Card identifier changed or disappeared. Select the card again before importing.")
                }
            } catch {
                log(error.localizedDescription)
                return 1
            }
        }
        let inventory: PhotoInventory
        let planner: PhotoPlanner
        do {
            inventory = try PhotoInventory(destination: options.destination, readOnly: options.dryRun)
            planner = try PhotoPlanner(options: options, records: inventory.records())
        } catch {
            log(error.localizedDescription)
            return 1
        }

        var extensions = photoExtensions
        if !options.excludeMovies { extensions.formUnion(videoExtensions) }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey,
                                        .contentModificationDateKey, .fileSizeKey]
        var copied = 0, skipped = 0, failures = 0
        guard let walker = manager.enumerator(at: source, includingPropertiesForKeys: Array(keys),
                                               errorHandler: { url, error in
            log("Cannot read \(url.path): \(error.localizedDescription)")
            failures += 1
            return true
        }) else {
            log("Cannot read \(source.path)")
            return 1
        }

        for case let file as URL in walker {
            if isCancelled() {
                log("Cancelled.")
                return 1
            }
            let name = file.lastPathComponent
            // Cards from some cameras carry AppleDouble companions that are not photos.
            guard !name.hasPrefix("._"), extensions.contains(file.pathExtension.lowercased()) else { continue }
            do {
                let values = try file.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                guard let date = values.creationDate else {
                    log("Skipping (no creation date): \(file.path)")
                    skipped += 1
                    continue
                }
                guard options.includes(date) else { continue }
                // Enumeration may expand /var to /private/var; use depth rather than
                // subtracting an absolute path prefix to keep identity independent of mount location.
                let relativePath = file.pathComponents.suffix(walker.level).joined(separator: "/")
                let size = Int64(values.fileSize ?? 0)
                let plan = try planner.plan(deviceID: identity, sourcePath: relativePath, name: name,
                                            date: date, sourceSize: size)
                if plan.adopt {
                    try inventory.reserve(plan.record, deviceName: job.source.label, originalName: name,
                                          date: date, sourceSize: size, modified: values.contentModificationDate)
                    log("\(options.dryRun ? "[DRY RUN] Would adopt" : "Adopted") existing file for this card: \(plan.target.path)")
                }
                if plan.skip {
                    if !plan.adopt {
                        log("Skipping (\(plan.deleted ? "previously imported; deleted locally" : "already imported from this card")): \(plan.target.path)")
                    }
                    skipped += 1
                } else if options.dryRun {
                    log("[DRY RUN] Would \(plan.replace ? "replace" : "copy"): \"\(file.path)\" → \"\(plan.target.path)\"")
                } else {
                    try inventory.reserve(plan.record, deviceName: job.source.label, originalName: name,
                                          date: date, sourceSize: size, modified: values.contentModificationDate)
                    if let existing = try copy(file, plan: plan, sourceSize: size, inventory: inventory,
                                               options: options, isCancelled: isCancelled) {
                        log("Skipping (identical content already imported from this card): \(existing.path)")
                        skipped += 1
                    } else {
                        log("\(plan.replace ? "Replaced" : "Copied"): \"\(file.path)\" → \"\(plan.target.path)\"")
                        copied += 1
                    }
                }
            } catch {
                log("Failed \(name): \(error.localizedDescription)")
                failures += 1
            }
        }
        log("Copied: \(copied); skipped: \(skipped); errors: \(failures)")
        return failures == 0 ? 0 : 1
    }

    // Stage the copy before committing it; an interrupted copy remains incomplete in the inventory.
    // A returned URL means identical content was linked to an existing inventory entry.
    private static func copy(_ file: URL, plan: PhotoPlan, sourceSize: Int64, inventory: PhotoInventory,
                             options: Options, isCancelled: () -> Bool) throws -> URL? {
        let manager = FileManager.default
        let target = plan.target
        let directory = target.deletingLastPathComponent()
        let root = options.destination.resolvingSymlinksInPath().path
        guard directory.resolvingSymlinksInPath().path.hasPrefix(root == "/" ? root : root + "/") else {
            throw ImportError(message: "Destination date folder escapes the import destination.")
        }
        if !plan.replace && (manager.fileExists(atPath: target.path)
            || (try? manager.destinationOfSymbolicLink(atPath: target.path)) != nil) {
            throw ImportError(message: "Target appeared after planning; refusing to overwrite it: \(target.path)")
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let partial = directory.appendingPathComponent(".card-import-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: partial) }
        try manager.copyItem(at: file, to: partial)
        let attributes = try manager.attributesOfItem(atPath: partial.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0, size == sourceSize else {
            throw ImportError(message: "Copied file is empty or its size changed during transfer: \(file.path)")
        }
        if isCancelled() { throw ImportError(message: "Cancelled.") }
        if let existing = try inventory.reuseIdenticalDownload(plan.record, downloaded: partial, size: size, options: options) {
            return existing
        }
        if plan.replace {
            guard rename(partial.path, target.path) == 0 else {
                throw ImportError(message: "Cannot replace \(target.path): \(String(cString: strerror(errno)))")
            }
        } else {
            try manager.moveItem(at: partial, to: target)
        }
        try inventory.complete(plan.record, size: size)
        return nil
    }
}
