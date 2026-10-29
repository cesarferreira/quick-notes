import Foundation

public struct Note: Equatable, Identifiable {
    public var id: String
    public var body: String
    public var modified: Date
    public init(id: String = UUID().uuidString + ".md", body: String = "", modified: Date = Date()) {
        self.id = id
        self.body = body
        self.modified = modified
    }
    public var title: String { Markdown.plainTitle(body) }
    public var preview: String {
        body.components(separatedBy: .newlines).dropFirst().joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

public enum NoteStoreError: LocalizedError {
    case invalidID, conflict, unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .invalidID: return "The note has an invalid filename."
        case .conflict: return "This note changed on disk. Your edits have been kept in a separate copy."
        case .unreadable(let filename): return "Could not read \(filename). Check the file’s permissions and UTF-8 encoding."
        }
    }
}

public final class NoteStore {
    public let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
    public func url(for note: Note) -> URL { directory.appendingPathComponent(note.id) }

    public func load() throws -> [Note] {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        return try files.filter { $0.pathExtension.lowercased() == "md" }.compactMap { file in
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            let body: String
            do { body = try String(contentsOf: file, encoding: .utf8) }
            catch { throw NoteStoreError.unreadable(file.lastPathComponent) }
            return Note(id: file.lastPathComponent, body: body,
                modified: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified == $1.modified ? $0.id < $1.id : $0.modified > $1.modified }
    }

    public func save(_ note: Note, expectedBody: String?) throws {
        guard !note.id.isEmpty, note.id != ".", note.id != "..",
              !note.id.contains("/"), !note.id.contains("\\"), !note.id.contains("\0"),
              (note.id as NSString).pathExtension.lowercased() == "md" else {
            throw NoteStoreError.invalidID
        }
        let file = url(for: note)
        let exists = FileManager.default.fileExists(atPath: file.path)
        if exists {
            let original = try String(contentsOf: file, encoding: .utf8)
            guard let expectedBody, original == expectedBody else { throw NoteStoreError.conflict }
        } else if expectedBody != nil {
            throw NoteStoreError.conflict
        }
        try note.body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    public func search(_ notes: [Note], query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
