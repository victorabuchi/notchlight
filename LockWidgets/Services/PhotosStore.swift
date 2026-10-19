import AppKit
import ImageIO
import Photos
import UniformTypeIdentifiers

/// Picks a photo to show, from the Photos library, a folder or photos you choose, and swaps it on a timer.
final class PhotosStore: ObservableObject {
    static let shared = PhotosStore()
    static let sourceKey = "photosSource"
    static let intervalKey = "photosInterval"
    private static let folderKey = "photosFolderBookmark"

    enum Source: String, CaseIterable, Identifiable {
        case favorites, recents, folder, chosen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .favorites: "Favourites"
            case .recents: "Recent photos"
            case .folder: "A folder"
            case .chosen: "Photos you choose"
            }
        }
    }

    /// A photo you chose, for the settings: its copy's file name and a small picture of it.
    struct ChosenPhoto: Identifiable, Equatable {
        let id: String
        let thumbnail: NSImage

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    @Published private(set) var image: NSImage?
    @Published private(set) var date: Date?
    @Published private(set) var problem: String?
    @Published private(set) var folderName: String?
    @Published private(set) var libraryAccess = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    @Published private(set) var chosen: [ChosenPhoto] = []

    private static let chosenKey = "photosChosen"
    private static let chosenDatesKey = "photosChosenDates"
    private static let chosenIndexKey = "photosChosenIndex"

    private var timer: Timer?

    private var source: Source {
        Source(rawValue: UserDefaults.standard.string(forKey: Self.sourceKey) ?? "") ?? .favorites
    }

    private init() {
        #if DEBUG
        if WidgetGallery.isRendering { return } // Sample data only.
        #endif
        folderName = resolveFolder()?.lastPathComponent
        loadChosen()
        next()
        restartTimer()
    }

    func restartTimer() {
        let minutes = UserDefaults.standard.object(forKey: Self.intervalKey) as? Int ?? 15
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            self?.next()
        }
    }

    func requestAccess() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                self?.libraryAccess = status == .authorized
                self?.next()
            }
        }
    }

    func next() {
        switch source {
        case .folder: nextFromFolder()
        case .favorites, .recents: nextFromLibrary()
        case .chosen: nextFromChosen()
        }
    }

    // MARK: Library

    private func nextFromLibrary() {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            publish(problem: "Allow Photos access in Notchlight settings.")
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 300
        if source == .favorites {
            options.predicate = NSPredicate(format: "favorite == YES")
        }
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else {
            publish(problem: source == .favorites ? "No favourite photos yet." : "No photos found.")
            return
        }
        let asset = assets.object(at: Int.random(in: 0 ..< assets.count))
        let request = PHImageRequestOptions()
        request.deliveryMode = .highQualityFormat
        request.isNetworkAccessAllowed = true
        request.resizeMode = .fast
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 900, height: 900), contentMode: .aspectFill, options: request) { [weak self] image, _ in
            guard let image else { return }
            DispatchQueue.main.async {
                self?.image = image
                self?.date = asset.creationDate
                self?.problem = nil
            }
        }
    }

    // MARK: Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder of photos to show on the lock screen."
        guard panel.runModal() == .OK, let url = panel.url,
              let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        UserDefaults.standard.set(bookmark, forKey: Self.folderKey)
        folderName = url.lastPathComponent
        next()
    }

    private func resolveFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.folderKey) else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private func nextFromFolder() {
        guard let folder = resolveFolder() else {
            publish(problem: "Choose a folder in Notchlight settings.")
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            let extensions: Set = ["jpg", "jpeg", "png", "heic", "tiff", "webp"]
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey]))?
                .filter { extensions.contains($0.pathExtension.lowercased()) } ?? []
            guard let file = files.randomElement(),
                  let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 900,
                  ] as CFDictionary)
            else {
                self?.publish(problem: "No photos found in that folder.")
                return
            }
            let created = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate
            let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            DispatchQueue.main.async {
                self?.image = image
                self?.date = created
                self?.problem = nil
            }
        }
    }

    // MARK: Photos you choose

    /// Copies of the photos you choose, in Notchlight's own folder, so they stay even if the originals move.
    private static var chosenFolder: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchlight/Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The copies' file names, in the order they're shown.
    private var chosenNames: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.chosenKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.chosenKey) }
    }

    /// Adds photos from files, as from Finder.
    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add Photos"
        panel.message = "Choose one photo to keep on the lock screen, or several to show one after another."
        guard panel.runModal() == .OK else { return }
        add(panel.urls.compactMap { try? Data(contentsOf: $0) })
    }

    /// Adds photos after the ones already chosen, such as those picked from the Photos library.
    func add(_ images: [Data]) {
        var names = chosenNames
        var dates = UserDefaults.standard.dictionary(forKey: Self.chosenDatesKey) as? [String: Double] ?? [:]
        for data in images {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1600,
                  ] as CFDictionary)
            else { continue }
            let name = UUID().uuidString + ".jpg"
            let url = Self.chosenFolder.appendingPathComponent(name)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { continue }
            names.append(name)
            if let taken = Self.dateTaken(source) { dates[name] = taken.timeIntervalSince1970 }
        }
        chosenNames = names
        UserDefaults.standard.set(dates, forKey: Self.chosenDatesKey)
        loadChosen()
        if source == .chosen, image == nil || problem != nil { next() }
    }

    func remove(_ id: String) {
        chosenNames.removeAll { $0 == id }
        try? FileManager.default.removeItem(at: Self.chosenFolder.appendingPathComponent(id))
        var dates = UserDefaults.standard.dictionary(forKey: Self.chosenDatesKey) as? [String: Double] ?? [:]
        dates[id] = nil
        UserDefaults.standard.set(dates, forKey: Self.chosenDatesKey)
        loadChosen()
        if source == .chosen { next() }
    }

    /// Moves a photo to just before another, as when it's dragged onto it; nil moves it to the end.
    func move(_ id: String, before target: String?) {
        var names = chosenNames
        guard let from = names.firstIndex(of: id) else { return }
        names.remove(at: from)
        if let target, let to = names.firstIndex(of: target) {
            names.insert(id, at: to)
        } else {
            names.append(id)
        }
        chosenNames = names
        loadChosen()
    }

    private func loadChosen() {
        chosen = chosenNames.compactMap { name in
            let url = Self.chosenFolder.appendingPathComponent(name)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 200,
                  ] as CFDictionary)
            else { return nil }
            return ChosenPhoto(id: name, thumbnail: NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height)))
        }
    }

    /// The next photo in your order; with one photo, that one stays.
    private func nextFromChosen() {
        let names = chosenNames
        guard !names.isEmpty else {
            publish(problem: "Choose photos in Notchlight settings.")
            return
        }
        let index = (UserDefaults.standard.object(forKey: Self.chosenIndexKey) as? Int).map { ($0 + 1) % names.count } ?? 0
        UserDefaults.standard.set(index, forKey: Self.chosenIndexKey)
        let url = Self.chosenFolder.appendingPathComponent(names[index])
        let taken = (UserDefaults.standard.dictionary(forKey: Self.chosenDatesKey) as? [String: Double])?[names[index]]
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let image = NSImage(contentsOf: url) else {
                self?.publish(problem: "That photo couldn't be opened. Choose it again in Notchlight settings.")
                return
            }
            let date = taken.map { Date(timeIntervalSince1970: $0) }
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
            DispatchQueue.main.async {
                self?.image = image
                self?.date = date
                self?.problem = nil
            }
        }
    }

    /// When a photo was taken, from its camera information.
    private static func dateTaken(_ source: CGImageSource) -> Date? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
        guard let text = exif?[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    private func publish(problem: String) {
        DispatchQueue.main.async { self.problem = problem }
    }
}

#if DEBUG
extension PhotosStore {
    func loadSample(_ photo: NSImage?) {
        image = photo
        date = Calendar.current.date(byAdding: .month, value: -3, to: .now)
        problem = nil
        libraryAccess = true
    }
}
#endif
