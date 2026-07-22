import Foundation

enum ImportError: LocalizedError {
    case unsupported(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext): return "Unsupported file type: .\(ext). Use .erg, .mrc, or .zwo."
        case .unreadable: return "Couldn't read the file as text."
        }
    }
}

enum ImportWorkout {
    /// Dispatches on file extension to the right parser.
    static func from(url: URL) throws -> Workout {
        let ext = url.pathExtension.lowercased()
        // Security-scoped resource access for files coming from the Files app / iCloud.
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        return try from(text: text, ext: ext)
    }

    static func from(text: String, ext: String) throws -> Workout {
        switch ext {
        case "erg", "mrc":
            return try ErgFileParser.parse(text)
        case "zwo", "xml":
            return try ZwoParser.parse(text)
        default:
            throw ImportError.unsupported(ext)
        }
    }
}
