import Foundation

/// A date-only diary key. The persisted day is independent of the device's time zone.
/// `Date` remains the UI boundary and resolves to that day in the current local time zone.
struct DiaryDay: Codable, Equatable, Sendable {
    let rawValue: String

    init(_ date: Date) {
        let seconds = date.timeIntervalSince1970
        // Guard before invoking Calendar/ICU, which cannot safely convert arbitrary doubles.
        guard seconds.isFinite, seconds >= -62_135_683_200, seconds < 253_402_387_200 else {
            rawValue = ""
            return
        }
        let components = Self.calendar(timeZone: Calendar.current.timeZone).dateComponents([.era, .year, .month, .day], from: date)
        guard components.era == 1, let year = components.year, (1...9999).contains(year),
              let month = components.month, let day = components.day else {
            rawValue = ""
            return
        }
        rawValue = String(format: "%04d-%02d-%02d", year, month, day)
    }

    var date: Date {
        resolved(in: Calendar.current.timeZone) ?? Date(timeIntervalSinceReferenceDate: .nan)
    }

    private func resolved(in timeZone: TimeZone) -> Date? {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard rawValue.utf8.count == 10, parts.count == 3, parts[0].count == 4,
              parts[1].count == 2, parts[2].count == 2,
              rawValue.allSatisfy({ $0 == "-" || $0.isASCII && $0.isNumber }),
              let year = Int(parts[0]), (1...9999).contains(year),
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), (1...31).contains(day) else { return nil }
        let calendar = Self.calendar(timeZone: timeZone)
        guard let result = calendar.date(from: DateComponents(era: 1, year: year, month: month, day: day)) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day], from: result)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        return result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
        guard resolved(in: TimeZone(secondsFromGMT: 0)!) != nil else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Gregorian diary day; expected yyyy-MM-dd in years 0001...9999.")
        }
    }

    func encode(to encoder: Encoder) throws {
        guard resolved(in: TimeZone(secondsFromGMT: 0)!) != nil else {
            throw EncodingError.invalidValue(rawValue, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Invalid diary day."))
        }
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
