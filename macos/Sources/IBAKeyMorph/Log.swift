import AppKit

/// Plain-text log in ~/Library/Logs/IBA KeyMorph/keymorph.log (also listed in Console.app).
/// Lines are mirrored to stderr, so running the binary from Terminal shows them live.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/IBA KeyMorph/keymorph.log")

    private static let maxSize = 1_000_000
    private static let queue = DispatchQueue(label: "com.iba.keymorph.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        queue.async { append(line) }
    }

    /// Opens the log in the default viewer (Console), creating it first if needed.
    static func open() {
        if !FileManager.default.fileExists(atPath: url.path) {
            info("Журнал создан")
        }

        queue.sync {}
        NSWorkspace.shared.open(url)
    }

    private static func append(_ line: String) {
        let files = FileManager.default
        try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? files.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxSize {
            let old = url.deletingPathExtension().appendingPathExtension("old.log")
            try? files.removeItem(at: old)
            try? files.moveItem(at: url, to: old)
        }

        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? Data(line.utf8).write(to: url)
            return
        }

        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }
}
