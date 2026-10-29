import Foundation

public struct MarkdownLine: Equatable {
    public var range: NSRange
    public var bodyRange: NSRange
    public var markerRange: NSRange?
    public var checkRange: NSRange?
    public var checked: Bool
    public var indent: Int
    public var heading: Int
    public var isCode: Bool
}

public enum Markdown {
    private static let task = try! NSRegularExpression(pattern: #"^([ \t]*)(?:[-*+] )?\[([ xX])\] "#)
    private static let heading = try! NSRegularExpression(pattern: #"^(#{1,6}) "#)
    private static let list = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+]|[0-9]+\.) "#)

    public static func lines(_ source: String) -> [MarkdownLine] {
        let text = source as NSString
        var result: [MarkdownLine] = []
        var offset = 0
        var fence: String?
        while offset < text.length {
            let fullRange = text.lineRange(for: NSRange(location: offset, length: 0))
            let raw = text.substring(with: fullRange).trimmingCharacters(in: .newlines)
            let local = NSRange(location: 0, length: (raw as NSString).length)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let fenceMarker = trimmed.hasPrefix("```") ? "```" : (trimmed.hasPrefix("~~~") ? "~~~" : nil)
            let code = fence != nil || fenceMarker != nil
            if let marker = fenceMarker {
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
            }
            var line = MarkdownLine(range: fullRange,
                bodyRange: NSRange(location: offset, length: local.length),
                markerRange: nil, checkRange: nil, checked: false,
                indent: 0, heading: 0, isCode: code)
            if !code, let match = task.firstMatch(in: raw, range: local) {
                let whitespace = (raw as NSString).substring(with: match.range(at: 1))
                line.indent = whitespace.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
                line.markerRange = NSRange(location: offset, length: match.range.length)
                let check = match.range(at: 2)
                line.checkRange = NSRange(location: offset + check.location, length: 1)
                line.checked = (raw as NSString).substring(with: check).lowercased() == "x"
                line.bodyRange = NSRange(location: offset + match.range.length, length: local.length - match.range.length)
            } else if !code, let match = heading.firstMatch(in: raw, range: local) {
                line.heading = match.range(at: 1).length
                line.markerRange = NSRange(location: offset, length: match.range.length)
                line.bodyRange = NSRange(location: offset + match.range.length, length: local.length - match.range.length)
            }
            result.append(line)
            offset = NSMaxRange(fullRange)
        }
        return result
    }

    public static func togglingTask(_ source: String, at offset: Int) -> String {
        guard let line = lines(source).first(where: { NSLocationInRange(offset, $0.range) }),
              let check = line.checkRange else { return source }
        return (source as NSString).replacingCharacters(in: check, with: line.checked ? " " : "x")
    }

    public static func newline(in source: String, at selection: NSRange) -> (range: NSRange, text: String) {
        let text = source as NSString
        guard selection.location <= text.length,
              let line = lines(source).first(where: { selection.location >= $0.range.location && selection.location <= NSMaxRange($0.bodyRange) }),
              !line.isCode, line.heading == 0 else { return (selection, "\n") }
        if let marker = line.markerRange, line.checkRange != nil {
            guard selection.location >= NSMaxRange(marker) else { return (selection, "\n") }
            if text.substring(with: line.bodyRange).trimmingCharacters(in: .whitespaces).isEmpty {
                return (NSRange(location: line.range.location, length: NSMaxRange(selection) - line.range.location), "")
            }
            let prefix = text.substring(with: marker)
            let unchecked = prefix.replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            return (selection, "\n" + unchecked)
        }
        let raw = text.substring(with: line.bodyRange)
        if let match = list.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
            guard selection.location >= line.range.location + match.range.length else { return (selection, "\n") }
            if (raw as NSString).length == match.range.length {
                return (NSRange(location: line.range.location, length: NSMaxRange(selection) - line.range.location), "")
            }
            let indent = (raw as NSString).substring(with: match.range(at: 1))
            let bullet = (raw as NSString).substring(with: match.range(at: 2))
            if let number = Int(bullet.dropLast()), number < Int.max {
                return (selection, "\n\(indent)\(number + 1). ")
            }
            return (selection, "\n\(indent)\(bullet) ")
        }
        return (selection, "\n")
    }

    public static func plainTitle(_ source: String) -> String {
        for line in lines(source) {
            let raw = (source as NSString).substring(with: line.bodyRange).trimmingCharacters(in: .whitespaces)
            if !raw.isEmpty {
                return String(raw.replacingOccurrences(of: #"[*_`~]"#, with: "", options: .regularExpression).prefix(80))
            }
        }
        return "Untitled note"
    }
}
