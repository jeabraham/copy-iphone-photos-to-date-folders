import Photos

// Only original resources are exported; edited renders and adjustment data are skipped.
enum OriginalResource {
    static func name(for type: PHAssetResourceType) -> String? {
        switch type {
        case .photo: return "photo"
        case .video: return "video"
        case .alternatePhoto: return "alternatePhoto"
        case .pairedVideo: return "pairedVideo"
        default: return nil
        }
    }

    static func isMovie(_ name: String) -> Bool { name == "video" || name == "pairedVideo" }
}

enum PhotoLibrary {
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func list(from: Date?, to: Date?, excludeMovies: Bool) -> [[String: Any]] {
        let options = PHFetchOptions()
        var predicates: [NSPredicate] = []
        if let from = from { predicates.append(NSPredicate(format: "creationDate >= %@", from as NSDate)) }
        if let to = to { predicates.append(NSPredicate(format: "creationDate < %@", to as NSDate)) }
        if !predicates.isEmpty { options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
        var assets: [[String: Any]] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard let date = asset.creationDate else { return }
            let resources: [[String: Any]] = PHAssetResource.assetResources(for: asset).compactMap {
                guard let type = OriginalResource.name(for: $0.type),
                      !(excludeMovies && OriginalResource.isMovie(type)) else { return nil }
                return ["type": type, "name": $0.originalFilename]
            }
            if !resources.isEmpty {
                assets.append(["id": asset.localIdentifier, "date": date.timeIntervalSince1970, "resources": resources])
            }
        }
        return assets
    }

    static func resource(assetID: String, type: String, name: String) -> PHAssetResource? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        return PHAssetResource.assetResources(for: asset).first {
            OriginalResource.name(for: $0.type) == type && $0.originalFilename == name
        }
    }
}
