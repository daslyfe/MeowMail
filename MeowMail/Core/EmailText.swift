import Foundation

enum HTMLText {
    /// Converts HTML to readable text. `dropQuotes` removes quoted history blocks.
    static func plain(_ html: String, dropQuotes: Bool = false) -> String {
        var text = html
        text = replace(text, "(?is)<(head|style|script|title)\\b.*?</\\1\\s*>", "")
        text = replace(text, "(?s)<!--.*?-->", "")
        if dropQuotes {
            text = replace(text, "(?is)<div[^>]*class=\"[^\"]*gmail_quote[^\"]*\".*$", "")
            text = replace(text, "(?is)<blockquote\\b[^>]*type=\"cite\".*$", "")
            text = replace(text, "(?is)<div[^>]*(id|class)=\"[^\"]*(divRplyFwdMsg|moz-cite-prefix|yahoo_quoted)[^\"]*\".*$", "")
        }
        text = replace(text, "(?i)<br\\s*/?>", "\n")
        text = replace(text, "(?i)</(p|div|tr|li|h[1-6]|blockquote)\\s*>", "\n")
        text = replace(text, "<[^>]+>", "")
        text = decodeEntities(text)
        text = replace(text, "[ \\t]+\\n", "\n")
        text = replace(text, "\\n{3,}", "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Newsletter-style mail relies on its layout, so it is shown as designed.
    static func isRichLayout(_ html: String) -> Bool {
        let lower = html.lowercased()
        if lower.contains("gmail_quote") || lower.contains("gmail_default") { return false }
        return lower.components(separatedBy: "<table").count > 3
            || lower.components(separatedBy: "<img").count > 3
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    private static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        var result = text
        for (entity, value) in named {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        let regex = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for match in regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result),
                  let hexFlag = Range(match.range(at: 1), in: result),
                  let digits = Range(match.range(at: 2), in: result),
                  let code = UInt32(result[digits], radix: result[hexFlag].isEmpty ? 10 : 16),
                  let scalar = Unicode.Scalar(code) else { continue }
            result.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}

enum QuoteStripper {
    /// Removes trailing quoted history and signatures. Falls back to the full
    /// text if that would leave nothing, so a message can never appear blank.
    static func strip(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")

        if let cut = firstCut(in: lines) {
            lines = Array(lines[..<cut])
        }
        while let last = lines.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix(">") {
                lines.removeLast()
            } else {
                break
            }
        }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? normalized.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    private static func firstCut(in lines: [String]) -> Int? {
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if raw == "-- " || line == "--" || line == "—" { return index }
            if line.range(of: "^-{2,}\\s*(Original|Forwarded) Message\\s*-{2,}$",
                          options: [.regularExpression, .caseInsensitive]) != nil { return index }
            if line.range(of: "^_{10,}$", options: .regularExpression) != nil { return index }
            if line.range(of: "^Sent from (my |Mail for |Yahoo|Outlook)",
                          options: [.regularExpression, .caseInsensitive]) != nil { return index }
            if line.range(of: "^Get Outlook for ", options: .caseInsensitive) != nil { return index }

            // "On <date>, <name> wrote:" can wrap onto a second or third line.
            if line.hasPrefix("On ") {
                let joined = lines[index..<min(index + 3, lines.count)].joined(separator: " ")
                if joined.range(of: "^\\s*On .{5,200}\\swrote:", options: .regularExpression) != nil {
                    return index
                }
            }

            // Outlook's "From: ... Sent: ..." block.
            if line.hasPrefix("From:"), index + 1 < lines.count {
                let next = lines[(index + 1)..<min(index + 4, lines.count)]
                if next.contains(where: { $0.hasPrefix("Sent:") || $0.hasPrefix("Date:") }) {
                    return index
                }
            }
        }
        return nil
    }
}
