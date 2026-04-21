import Foundation
import os.log

// Persistent activity log stored as JSON under Application Support/DevDiary
final class ActivityLogService {
    static let shared = ActivityLogService()
    private let logger = Logger(subsystem: "com.devdiary", category: "ActivityLog")
    private init() {
        // Attempt compaction on init
        pruneOldEntries()
    }

    enum Kind: String, Codable { case success, error, info }

    struct Entry: Codable, Equatable {
        var date: Date
        var kind: Kind
        var text: String
    }

    private var cached: [Entry] = []
    private let fileName = "activity-log.json"
    private let retentionKey = "activityLogRetentionDays"

    var retentionDays: Int {
        let days = UserDefaults.standard.integer(forKey: retentionKey)
        return days > 0 ? days : 30
    }

    // MARK: - Public API
    func load() -> [Entry] {
        if !cached.isEmpty { return cached }
        let url = fileURL()
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            let entries = try JSONDecoder().decode([Entry].self, from: data)
            cached = entries
            return entries
        } catch {
            logger.error("Failed to decode activity log: \(error.localizedDescription)")
            return []
        }
    }

    @discardableResult
    func append(kind: Kind, text: String, date: Date = Date()) -> [Entry] {
        var entries = load()
        entries.append(.init(date: date, kind: kind, text: text))
        cached = entries
        save(entries)
        pruneOldEntries()
        return cached
    }

    func clear() {
        cached = []
        save([])
    }

    func setRetentionDays(_ days: Int) {
        UserDefaults.standard.set(days, forKey: retentionKey)
        pruneOldEntries()
    }

    func pruneOldEntries() {
        guard !cached.isEmpty || FileManager.default.fileExists(atPath: fileURL().path) else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let entries = load().filter { $0.date >= cutoff }
        if entries != cached {
            cached = entries
            save(entries)
        }
    }

    // MARK: - Private
    private func fileURL() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("DevDiary", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func save(_ entries: [Entry]) {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL(), options: [.atomic])
        } catch {
            logger.error("Failed to write activity log: \(error.localizedDescription)")
        }
    }
}
