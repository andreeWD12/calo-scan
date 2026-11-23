import UIKit

/// Miniature delle foto dei pasti scansionati. Restano solo su questo dispositivo
/// (Application Support, escluse dal backup iCloud, protette finché il telefono è bloccato):
/// non vengono mai caricate sui server. Si cancellano con il pasto, all'uscita e all'eliminazione dell'account.
actor MealPhotoStore {
    static let shared = MealPhotoStore()

    private let directory: URL
    private var cache: [UUID: UIImage] = [:]

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MealPhotos", isDirectory: true)
        self.directory = base
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).jpg") }

    private func prepareDirectory() throws {
        var dir = directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
    }

    /// Salva una miniatura (lato lungo 240 px) dalla foto originale.
    func save(jpegData: Data, for id: UUID) {
        guard let image = UIImage(data: jpegData) else { return }
        let side: CGFloat = 240
        let scale = min(side / max(image.size.width, image.size.height), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumb = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = thumb.jpegData(compressionQuality: 0.7) else { return }
        do {
            try prepareDirectory()
            try data.write(to: url(for: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            cache[id] = thumb
        } catch {
            Log.app.error("Miniatura non salvata")
        }
    }

    func thumbnail(for id: UUID) -> UIImage? {
        if let cached = cache[id] { return cached }
        guard let data = try? Data(contentsOf: url(for: id)), let image = UIImage(data: data) else { return nil }
        cache[id] = image
        return image
    }

    func remove(_ id: UUID) {
        cache[id] = nil
        try? FileManager.default.removeItem(at: url(for: id))
    }

    func removeAll() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
