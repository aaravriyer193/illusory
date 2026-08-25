import Foundation

/// Recent file-system activity in whichever directory the user is actually working
/// in. This is the piece that makes the flagship case possible: "rename the other
/// forty-eight" is only inferable if Illusory can see that two files were renamed
/// minutes ago and forty-eight siblings still carry the old scheme.
enum FileActivity {
    struct Entry {
        let name: String
        let modified: Date
        let isDirectory: Bool
        let size: Int
    }

    struct Report {
        let directory: String
        let total: Int
        let recentlyChanged: [Entry]
        let sample: [Entry]

        var description: String {
            var lines = ["Directory: \(directory) (\(total) items)"]
            if !recentlyChanged.isEmpty {
                lines.append("Changed in the last 30 minutes, newest first:")
                lines += recentlyChanged.map { "  \($0.name)  (\(Self.ago($0.modified)))" }
            }
            if !sample.isEmpty {
                lines.append("Other items in the same folder:")
                lines += sample.map { "  \($0.name)" }
            }
            return lines.joined(separator: "\n")
        }

        private static func ago(_ date: Date) -> String {
            let seconds = Int(Date().timeIntervalSince(date))
            if seconds < 60 { return "\(seconds)s ago" }
            if seconds < 3600 { return "\(seconds / 60)m ago" }
            return "\(seconds / 3600)h ago"
        }
    }

    /// `sampleLimit` is deliberately generous: seeing the *unchanged* siblings is
    /// what reveals the naming scheme that hasn't been applied yet.
    static func report(for directory: String,
                       window: TimeInterval = 1800,
                       recentLimit: Int = 12,
                       sampleLimit: Int = 30) -> Report? {
        let url = URL(fileURLWithPath: directory)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .fileSizeKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return nil }

        let entries: [Entry] = contents.compactMap { item in
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(name: item.lastPathComponent,
                         modified: values.contentModificationDate ?? .distantPast,
                         isDirectory: values.isDirectory ?? false,
                         size: values.fileSize ?? 0)
        }

        let cutoff = Date().addingTimeInterval(-window)
        let changed = entries.filter { $0.modified > cutoff }
            .sorted { $0.modified > $1.modified }
            .prefix(recentLimit)
        let changedNames = Set(changed.map(\.name))
        let rest = entries.filter { !changedNames.contains($0.name) }
            .sorted { $0.name < $1.name }
            .prefix(sampleLimit)

        return Report(directory: directory, total: entries.count,
                      recentlyChanged: Array(changed), sample: Array(rest))
    }

    /// Where to look when the frontmost app gives no directory of its own.
    static func fallbackDirectories() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Desktop", "Downloads"].map { home.appendingPathComponent($0).path }
    }

    /// Picks the folder with the most recent activity, which is nearly always the
    /// one the user is actually working in.
    static func mostActiveFallback() -> Report? {
        fallbackDirectories()
            .compactMap { report(for: $0) }
            .filter { !$0.recentlyChanged.isEmpty }
            .max { a, b in
                (a.recentlyChanged.first?.modified ?? .distantPast)
                    < (b.recentlyChanged.first?.modified ?? .distantPast)
            }
    }
}
