import Foundation
import ImageIO
import Photos
import PokiCore
import UniformTypeIdentifiers

/// Photo-library search, original export, saving and album membership through PhotoKit. Searches keep
/// the complete `localIdentifier`; exports preserve the original resource's filename and format;
/// writes use add-only authorization when no album is touched and read/write only when it is.
enum PhotoTools {
    static let specs: [ToolSpec] = [
        .make("photos_find",
              "Find photos and videos by creation date range, album name or id, type, or a location and radius. Returns the complete localIdentifier of each asset, its date, type and, when asked, its place. Results are paged with offset; a limited library is marked.",
              [
                "start": ["type": "string", "description": "Earliest creation date, ISO 8601 or yyyy-MM-dd."],
                "end": ["type": "string", "description": "Latest creation date, ISO 8601 or yyyy-MM-dd (the day is included)."],
                "album": ["type": "string", "description": "Album name; omit to search the library."],
                "album_id": ["type": "string", "description": "An album id from photos_albums."],
                "kind": ["type": "string", "enum": ["photo", "video", "all"]],
                "latitude": ["type": "number"],
                "longitude": ["type": "number"],
                "radius_km": ["type": "number", "minimum": 0.1, "maximum": 500],
                "limit": ["type": "integer", "minimum": 1, "maximum": 100],
                "offset": ["type": "integer", "minimum": 0],
              ], []),
        .make("photos_export",
              "Export the original resources of photos or videos to the app's photo workspace, including iCloud originals and, for a Live Photo or RAW, each original resource. Returns absolute file paths, the original filenames and a JPEG preview when the asset is a photo. Pass the localIdentifier from photos_find.",
              [
                "ids": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 20],
                "id": ["type": "string"],
              ], []),
        .make("photos_save",
              "Save a processed image or video from the app's photo workspace to the photo library. With album, the asset is added to that album in the same transaction (creating it when missing). Without album only add-only permission is used. request_id makes a retry idempotent.",
              [
                "path": ["type": "string", "description": "A path returned by photos_export, or a file in the app's photo workspace."],
                "album": ["type": "string"],
                "request_id": ["type": "string"],
              ], ["path"]),
        .make("photos_add_to_album",
              "Add existing photos or videos, by localIdentifier, to a named album. The album is created when it does not exist. Each asset is reported. request_id makes a retry idempotent.",
              [
                "ids": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 50],
                "album": ["type": "string"],
                "request_id": ["type": "string"],
              ], ["ids", "album"]),
        .make("photos_albums",
              "List the photo library's albums and smart albums with their ids and asset counts, marking a limited library.",
              [:], []),
    ]

    // MARK: Find

    static func find(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let access = await authorize(.readWrite) else {
            return NativeToolAnswer.permission("Photo library access is not allowed. Open Settings › Privacy & Security › Photos and allow Poki. Nothing was read.")
        }
        let (start, end) = dateRange(args)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var predicates: [NSPredicate] = []
        if let start { predicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate)) }
        if let end { predicates.append(NSPredicate(format: "creationDate < %@", end as NSDate)) }
        switch (args.string("kind") ?? "all").lowercased() {
        case "photo": predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue))
        case "video": predicates.append(NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue))
        default: break
        }
        if !predicates.isEmpty { options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates) }
        let album: PHAssetCollection?
        if let albumID = args.string("album_id") {
            let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
            guard let found = result.firstObject else { return NativeToolAnswer.empty("no album has id \(albumID).") }
            album = found
        } else if let name = args.string("album") {
            let found = albumCollections().filter { title($0).compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if found.count > 1 {
                return NativeToolAnswer.ambiguous("more than one album is named “\(name)”: \(found.map { "\(title($0)) (\($0.localIdentifier))" }.joined(separator: ", ")). Ask the owner which one; nothing was read.")
            }
            guard let only = found.first else { return NativeToolAnswer.empty("no album is named “\(name)”. Albums: \(albumCollections().map(title).joined(separator: ", ")); nothing was read.") }
            album = only
        } else {
            album = nil
        }
        let fetched = album.map { PHAsset.fetchAssets(in: $0, options: options) } ?? PHAsset.fetchAssets(with: options)
        let location = coordinate(args)
        let radius = args.double("radius_km")
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in
            if let location, let place = asset.location {
                let limit = (radius ?? 5) * 1000
                if place.distance(from: CLLocation(latitude: location.latitude, longitude: location.longitude)) > limit { return }
            }
            assets.append(asset)
        }
        guard !assets.isEmpty else {
            let kind = args.string("kind") ?? "photos or videos"
            let albumPart = album.map { " in \(title($0))" } ?? ""
            let datePart = start.map { " from \(NativeDate.display($0))" } ?? ""
            let limitedPart = access == .limited ? " The library is limited to the items shared with Poki." : ""
            return NativeToolAnswer.empty("no \(kind) matched\(albumPart)\(datePart).\(limitedPart)")
        }
        let offset = max(0, args.int("offset") ?? 0)
        let limit = min(100, max(1, args.int("limit") ?? 30))
        let page = assets.dropFirst(offset).prefix(limit)
        guard !page.isEmpty else {
            return NativeToolAnswer.empty("there are \(assets.count) matches, but offset \(offset) is past the end.")
        }
        let lines = page.map { asset -> String in
            var line = "- \(asset.localIdentifier) — \(asset.mediaType == .video ? "video" : "photo")"
            if let date = asset.creationDate { line += " — \(NativeDate.display(date))" }
            if asset.mediaType == .video { line += " — \(Int(asset.duration.rounded())) s" }
            if args.double("latitude") != nil, let place = asset.location {
                line += " — \(String(format: "%.5f,%.5f", place.coordinate.latitude, place.coordinate.longitude))"
            }
            return line
        }
        var text = "photos: \(page.count) of \(assets.count) matches\(access == .limited ? " (limited library)" : "")\n" + lines.joined(separator: "\n")
        if offset + page.count < assets.count { text += "\noffset \(offset + page.count) continues." }
        return NativeToolAnswer.ok(text)
    }

    // MARK: Export

    static func export(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        var ids = args.values["ids"] as? [String] ?? []
        if let single = args.string("id") { ids.append(single) }
        ids = ids.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !ids.isEmpty else { return NativeToolAnswer.invalid("ids is required; nothing was exported") }
        guard ids.count <= 20 else { return NativeToolAnswer.invalid("export at most 20 assets at a time; nothing was exported") }
        guard let access = await authorize(.readWrite) else {
            return NativeToolAnswer.permission("Photo library access is not allowed. Open Settings › Privacy & Security › Photos and allow Poki. Nothing was exported.")
        }
        let assets = ids.compactMap { asset(withIdentifier: $0) }
        guard !assets.isEmpty else { return NativeToolAnswer.empty("none of those photo identifiers was found; nothing was exported.") }
        let missing = ids.count - assets.count
        let directory: URL
        do {
            directory = try NativeWorkspace.newDirectory(in: NativeWorkspace.photoExports, prefix: "export")
        } catch {
            return NativeToolAnswer.failed("could not make the export folder: \(error.localizedDescription)")
        }
        var written: [String] = []
        var failures: [String] = []
        var preview: Data?
        for (index, asset) in assets.enumerated() {
            let resources = PHAssetResource.assetResources(for: asset).filter { exportable($0.type) }
            if resources.isEmpty {
                failures.append("\(asset.localIdentifier) has no original resource to export")
                continue
            }
            var assetNames: [String] = []
            for (resourceIndex, resource) in resources.enumerated() {
                let fallback = "asset-\(index + 1)-\(resourceIndex + 1)"
                let name = uniqueName(NativeWorkspace.safeName(resource.originalFilename, fallback: fallback), in: directory)
                let url = directory.appendingPathComponent(name)
                do {
                    try await write(resource, to: url)
                    written.append(url.path)
                    assetNames.append(name)
                    if preview == nil, let image = jpegPreview(of: url) { preview = image }
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    failures.append("\(asset.localIdentifier) / \(resource.originalFilename): \(error.localizedDescription)")
                }
            }
            if assetNames.isEmpty { failures.append("\(asset.localIdentifier) could not be written") }
        }
        if written.isEmpty {
            try? FileManager.default.removeItem(at: directory)
            return NativeToolAnswer.failed("no original could be exported. \(failures.joined(separator: "; "))")
        }
        var text = "exported: \(written.count) file\(written.count == 1 ? "" : "s") for \(assets.count) asset\(assets.count == 1 ? "" : "s")\(access == .limited ? " (limited library)" : "")\n"
        text += written.map { "- \($0)" }.joined(separator: "\n")
        if missing > 0 { text += "\nnot found: \(missing) identifier\(missing == 1 ? "" : "s")" }
        if !failures.isEmpty { text += "\npartial failures:\n" + failures.map { "- \($0)" }.joined(separator: "\n") }
        text += "\nfolder: \(directory.path)"
        return PokiCore.ToolAnswer(text: text, jpeg: preview, isError: false)
    }

    // MARK: Save

    static func save(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let raw = args.string("path") else { return NativeToolAnswer.invalid("path is required; nothing was saved") }
        let url = URL(fileURLWithPath: raw)
        guard NativeWorkspace.contains(url, in: NativeWorkspace.photoExports) || NativeWorkspace.contains(url, in: NativeWorkspace.sharedImports) else {
            return NativeToolAnswer.invalid("the path is outside the app's photo workspace; nothing was saved")
        }
        guard FileManager.default.fileExists(atPath: url.path), (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 > 0 else {
            return NativeToolAnswer.invalid("the file does not exist or is empty; nothing was saved")
        }
        let type = UTType(filenameExtension: url.pathExtension)
        let image = type?.conforms(to: .image) == true
        let video = type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true
        guard image || video else { return NativeToolAnswer.invalid("only an image or a video can be saved to the photo library; nothing was saved") }
        if let requestID = args.string("request_id"), let previous = WriteLedger.completed(requestID) {
            return NativeToolAnswer.ok("already saved: \(previous) (request_id \(requestID)); no second asset was added.")
        }
        let albumName = args.string("album")
        guard let access = await authorize(albumName == nil ? .addOnly : .readWrite) else {
            return NativeToolAnswer.permission("Photo library add access is not allowed. Open Settings › Privacy & Security › Photos and allow Poki. Nothing was saved.")
        }
        var album: PHAssetCollection?
        if let albumName {
            let found = albumCollections().filter { title($0).compare(albumName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if found.count > 1 {
                return NativeToolAnswer.ambiguous("more than one album is named “\(albumName)”: \(found.map { "\(title($0)) (\($0.localIdentifier))" }.joined(separator: ", ")). Ask the owner which one; nothing was saved.")
            }
            album = found.first
        }
        var identifier: String?
        var failure: String?
        let fileName = NativeWorkspace.safeName(url.lastPathComponent, fallback: "processed")
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = fileName
                    request.addResource(with: image ? .photo : .video, fileURL: url, options: options)
                    let placeholder = request.placeholderForCreatedAsset
                    identifier = placeholder?.localIdentifier
                    if let albumName {
                        if let album {
                            PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder].compactMap { $0 } as NSArray)
                        } else if let placeholder {
                            let created = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                            created.addAssets([placeholder] as NSArray)
                        }
                    }
                } completionHandler: { success, error in
                    if success { continuation.resume() } else { continuation.resume(throwing: error ?? PhotoFailure.save) }
                }
            }
        } catch {
            failure = error.localizedDescription
        }
        if let failure {
            return NativeToolAnswer.failed("the photo library could not save the file: \(failure). Nothing was saved.")
        }
        let albumPart = albumName.map { " in album \($0)" } ?? ""
        let idText = identifier ?? "unknown"
        let permission = access == .limited ? "limited library" : "add-only"
        let text = "saved: \(fileName)\(albumPart)\nid: \(idText)\npermission: \(permission)"
        if let requestID = args.string("request_id") { WriteLedger.record(requestID, value: text) }
        return NativeToolAnswer.ok(text)
    }

    // MARK: Albums

    static func addToAlbum(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let ids = (args.values["ids"] as? [String] ?? []).filter { !$0.isEmpty }
        let albumName = args.string("album")
        guard !ids.isEmpty else { return NativeToolAnswer.invalid("ids is required; nothing was added") }
        guard let albumName else { return NativeToolAnswer.invalid("album is required; nothing was added") }
        if let requestID = args.string("request_id"), let previous = WriteLedger.completed(requestID) {
            return NativeToolAnswer.ok("already added: \(previous) (request_id \(requestID)); no asset was added again.")
        }
        guard let access = await authorize(.readWrite) else {
            return NativeToolAnswer.permission("Photo library access is not allowed. Open Settings › Privacy & Security › Photos and allow Poki. Nothing was added.")
        }
        let assets = ids.compactMap { asset(withIdentifier: $0) }
        guard !assets.isEmpty else { return NativeToolAnswer.empty("none of those photo identifiers was found; nothing was added.") }
        let found = albumCollections().filter { title($0).compare(albumName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if found.count > 1 {
            return NativeToolAnswer.ambiguous("more than one album is named “\(albumName)”: \(found.map { "\(title($0)) (\($0.localIdentifier))" }.joined(separator: ", ")). Ask the owner which one; nothing was added.")
        }
        let album = found.first
        var added = false
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    if let album {
                        PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray)
                    } else {
                        let created = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                        created.addAssets(assets as NSArray)
                    }
                } completionHandler: { success, error in
                    if success { added = true; continuation.resume() } else { continuation.resume(throwing: error ?? PhotoFailure.save) }
                }
            }
        } catch {
            return NativeToolAnswer.failed("the album could not be updated: \(error.localizedDescription). Nothing was added.")
        }
        guard added else { return NativeToolAnswer.failed("the album change did not complete; nothing was added.") }
        let text = "added: \(assets.count) asset\(assets.count == 1 ? "" : "s") to \(album.map(title) ?? albumName)\(access == .limited ? " (limited library)" : "")\n" + assets.map { "- \($0.localIdentifier)" }.joined(separator: "\n")
        if let requestID = args.string("request_id") { WriteLedger.record(requestID, value: text) }
        return NativeToolAnswer.ok(text)
    }

    static func albums(_ arguments: String) async -> PokiCore.ToolAnswer {
        guard let access = await authorize(.readWrite) else {
            return NativeToolAnswer.permission("Photo library access is not allowed. Open Settings › Privacy & Security › Photos and allow Poki. Nothing was read.")
        }
        let collections = albumCollections()
        guard !collections.isEmpty else { return NativeToolAnswer.empty("the photo library has no albums.") }
        let lines = collections.map { collection -> String in
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            return "- \(title(collection)) — \(count) item\(count == 1 ? "" : "s") — \(collection.localIdentifier)"
        }
        return NativeToolAnswer.ok("albums: \(collections.count)\(access == .limited ? " (limited library)" : "")\n" + lines.joined(separator: "\n"))
    }

    // MARK: PhotoKit helpers

    private enum PhotoFailure: Error { case save }

    private static func authorize(_ level: PHAccessLevel) async -> PHAuthorizationStatus? {
        var status = PHPhotoLibrary.authorizationStatus(for: level)
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: level) { continuation.resume(returning: $0) }
            }
        }
        switch status {
        case .authorized, .limited: return status
        case .denied, .restricted: return nil
        case .notDetermined: return nil
        @unknown default: return nil
        }
    }

    private static func albumCollections() -> [PHAssetCollection] {
        var result: [PHAssetCollection] = []
        for type in [PHAssetCollectionType.album, .smartAlbum] {
            PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil).enumerateObjects { collection, _, _ in
                result.append(collection)
            }
        }
        return result.sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
    }

    private static func title(_ collection: PHAssetCollection) -> String {
        collection.localizedTitle?.nilIfEmpty ?? "(untitled album)"
    }

    private static func asset(withIdentifier raw: String) -> PHAsset? {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        let direct = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
        if let direct { return direct }
        if !id.contains("/") {
            return PHAsset.fetchAssets(withLocalIdentifiers: [id + "/L0/001"], options: nil).firstObject
        }
        return nil
    }

    private static func dateRange(_ args: ToolArgs) -> (Date?, Date?) {
        let start = args.date("start")
        var end = args.date("end")
        if let endDate = end, args.string("end")?.contains(":") == false {
            end = NativeDate.day(containing: endDate).1
        }
        return (start, end)
    }

    private static func coordinate(_ args: ToolArgs) -> (latitude: Double, longitude: Double)? {
        guard let latitude = args.double("latitude"), let longitude = args.double("longitude"),
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return (latitude, longitude)
    }

    private static func exportable(_ type: PHAssetResourceType) -> Bool {
        switch type {
        case .photo, .fullSizePhoto, .alternatePhoto, .video, .fullSizeVideo, .pairedVideo, .fullSizePairedVideo, .audio:
            return true
        default:
            return false
        }
    }

    private static func uniqueName(_ name: String, in directory: URL) -> String {
        let url = directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            for index in 2...999 {
                let candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
                if !FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) { return candidate }
            }
            return "\(base)-\(UUID().uuidString).\(ext)"
        }
        return name
    }

    private static func write(_ resource: PHAssetResource, to url: URL) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    /// A small JPEG for the model, made from the original file (ImageIO understands HEIC and RAW).
    private static func jpegPreview(of url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
