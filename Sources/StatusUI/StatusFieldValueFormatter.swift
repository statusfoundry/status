import Foundation
import StatusCore

enum StatusFieldValueTone: Equatable {
    case positive
    case warning
    case negative
    case neutral
}

enum StatusFieldValueFormatter {
    static func displayText(
        fieldID: String,
        label: String? = nil,
        value: String,
        kind: DashboardTileItemKind? = nil,
        actionURL: URL? = nil
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("true") == .orderedSame {
            return "Yes"
        }
        if trimmed.caseInsensitiveCompare("false") == .orderedSame {
            return "No"
        }
        if kind == .link, let url = actionURL ?? URL(string: trimmed) {
            return formattedURL(url)
        }
        if isMillisecondsField(fieldID) || label.map(isMillisecondsField) == true,
           Double(trimmed) != nil,
           trimmed.lowercased().hasSuffix("ms") == false {
            return "\(trimmed) ms"
        }
        return trimmed
    }

    static func tone(fieldID: String, value: String) -> StatusFieldValueTone? {
        let normalizedField = normalizedIdentifier(fieldID)
        let display = displayText(fieldID: fieldID, value: value).lowercased()
        let isStatusLikeField = normalizedField.contains("status") ||
            normalizedField.contains("state") ||
            normalizedField.contains("result") ||
            normalizedField.contains("severity") ||
            normalizedField.contains("reachable") ||
            normalizedField.contains("available") ||
            normalizedField.contains("healthy")
        let isStatusLikeValue = display == "yes" ||
            display == "no" ||
            display == "true" ||
            display == "false"
        guard isStatusLikeField || isStatusLikeValue else {
            return nil
        }
        if display == "no" ||
            display == "false" ||
            display.contains("fail") ||
            display.contains("reject") ||
            display.contains("critical") ||
            display.contains("down") {
            return .negative
        }
        if display.contains("review") ||
            display.contains("pending") ||
            display.contains("warning") ||
            display.contains("warn") ||
            display.contains("slow") {
            return .warning
        }
        if display == "yes" ||
            display == "true" ||
            display.contains("ok") ||
            display.contains("success") ||
            display.contains("ready") ||
            display.contains("up") {
            return .positive
        }
        return .neutral
    }

    private static func isMillisecondsField(_ value: String) -> Bool {
        let normalized = normalizedIdentifier(value)
        return normalized.hasSuffix("ms") ||
            normalized.contains("milliseconds") ||
            normalized.contains("responsetime")
    }

    private static func normalizedIdentifier(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func formattedURL(_ url: URL) -> String {
        guard let host = url.host(percentEncoded: false), host.isEmpty == false else {
            return url.absoluteString
        }
        let path = url.path(percentEncoded: false)
        return path == "/" || path.isEmpty ? host : "\(host)\(path)"
    }
}
