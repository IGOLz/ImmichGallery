import Foundation

/// Immich timestamps in timelines are "local wall-clock time". We parse and format them in UTC
/// so the displayed time matches when the photo was taken, wherever the viewer is.
enum ImmichDate {
    private static let utc = TimeZone(identifier: "UTC")!

    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func parse(_ string: String) -> Date? {
        var s = string
        if !s.hasSuffix("Z") && !s.contains("+") && s.count >= 19 { s += "Z" }
        if s.count == 10 { s += "T00:00:00Z" }
        return fractional.date(from: s) ?? plain.date(from: s)
    }

    static func monthTitle(_ bucket: String) -> String {
        guard let date = parse(String(bucket.prefix(10))) else { return bucket }
        return date.formatted(Date.FormatStyle(timeZone: utc).month(.wide).year())
    }

    static func long(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .shortened, timeZone: utc))
    }

    static func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: utc).weekday(.wide).day().month(.wide).year())
    }

    static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: utc))
    }
}

extension Duration {
    static func formatMilliseconds(_ ms: Int) -> String {
        Duration.milliseconds(ms).formatted(.time(pattern: ms >= 3_600_000 ? .hourMinuteSecond : .minuteSecond))
    }
}
