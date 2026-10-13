import Foundation

public enum DayWeatherCategory: String, Codable, Sendable, CaseIterable {
    case night, dawn, sunny, partlyCloudy, cloudy, lowLight, dusk
    case fog, drizzle, rain, ice, snow, storms
    case nightFog, nightDrizzle, nightRain, nightIce, nightSnow, nightStorms
    case unknown

    public var label: String {
        switch self {
        case .night: "Night"
        case .dawn: "Dawn"
        case .sunny: "Sunny"
        case .partlyCloudy: "Sun / Cloud"
        case .cloudy: "Cloudy"
        case .lowLight: "Low Light"
        case .dusk: "Dusk"
        case .fog: "Fog"
        case .drizzle: "Drizzle"
        case .rain: "Rain"
        case .ice: "Freezing Rain"
        case .snow: "Snow"
        case .storms: "Storms"
        case .nightFog: "Night Fog"
        case .nightDrizzle: "Night Drizzle"
        case .nightRain: "Night Rain"
        case .nightIce: "Night Ice"
        case .nightSnow: "Night Snow"
        case .nightStorms: "Night Storms"
        case .unknown: "Unavailable"
        }
    }

    var priority: Int {
        switch self {
        case .storms, .nightStorms: 6
        case .ice, .nightIce: 5
        case .snow, .nightSnow: 4
        case .rain, .nightRain: 3
        case .drizzle, .nightDrizzle: 2
        case .fog, .nightFog, .unknown: 1
        default: 0
        }
    }
}

public struct DayWeatherBlock: Codable, Equatable, Identifiable, Sendable {
    public let start: Date
    public let end: Date
    public let timeLabel: String
    public let accessibleTimeLabel: String
    public let categories: [DayWeatherCategory]

    public var id: Date { start }

    public var label: String {
        if categories.isEmpty { return "Unavailable" }
        if categories.count == 1 { return categories[0].label }
        if Set(categories).isSubset(of: [.sunny, .partlyCloudy, .cloudy]) {
            return DayWeatherCategory.partlyCloudy.label
        }
        // A short wet or stormy spell must remain visible when periods are combined.
        let ranked = categories.enumerated().sorted {
            $0.element.priority == $1.element.priority
                ? $0.offset < $1.offset
                : $0.element.priority > $1.element.priority
        }.map(\.element)
        if ranked.count == 2 {
            return ranked.map(\.label).joined(separator: " / ")
        }
        return ranked.first.map { "\($0.label) / Mix" } ?? "Unavailable"
    }
}

public struct DayTimeline: Codable, Equatable, Sendable {
    public let dateLabel: String
    public let timezone: String
    public let blocks: [DayWeatherBlock]

    /// Absolute intervals avoid confusing yesterday's cache or repeated DST hours
    /// with the current period. Endpoints belong to the following block.
    public func currentBlockID(at date: Date) -> Date? {
        blocks.first { $0.start <= date && date < $0.end }?.id
    }
}

public enum CityClock {
    /// Uses the saved city zone, never the device zone or a forecast's fixed offset.
    /// This is local formatting only; it does not refresh or mutate cached weather.
    public static func text(at date: Date, timezone identifier: String) -> String {
        guard let timezone = TimeZone(identifier: identifier) else { return "Time Unavailable" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let time = String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
        let abbreviation: String
        if identifier == "Asia/Kolkata" || identifier == "Asia/Calcutta" {
            abbreviation = "IST"
        } else {
            let style: TimeZone.NameStyle = timezone.isDaylightSavingTime(for: date)
                ? .shortDaylightSaving : .shortStandard
            abbreviation = timezone.localizedName(for: style, locale: Locale(identifier: "en_US"))
                ?? timezone.abbreviation(for: date) ?? identifier
        }
        return "\(time) \(abbreviation)"
    }
}

// Accept the previous ISO date response as well as unambiguous Unix timestamps.
enum ForecastTime: Decodable {
    case unix(Double)
    case iso(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let seconds = try? value.decode(Double.self), seconds.isFinite {
            self = .unix(seconds)
        } else {
            self = .iso(try value.decode(String.self))
        }
    }

    func date(in timezone: TimeZone) -> Date? {
        switch self {
        case .unix(let value):
            guard (0...32_503_680_000).contains(value) else { return nil }
            return Date(timeIntervalSince1970: value)
        case .iso(let value):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timezone
            formatter.dateFormat = value.count == 10 ? "yyyy-MM-dd" : "yyyy-MM-dd'T'HH:mm"
            formatter.isLenient = false
            return formatter.date(from: value)
        }
    }
}

struct HourlyResponse: Decodable {
    let time: [ForecastTime]
    let weatherCodes: [Int?]
    let isDay: [Int?]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCodes = "weather_code"
        case isDay = "is_day"
    }
}

enum DayTimelineBuilder {
    private struct Run {
        var start: Date
        var end: Date
        var categories: [DayWeatherCategory]
    }

    static func build(response: ForecastResponse, dailyIndex: Int, timezone: TimeZone) -> DayTimeline? {
        guard let hourly = response.hourly,
              let now = response.current.time?.date(in: timezone),
              (1...120).contains(hourly.time.count),
              hourly.time.count == hourly.weatherCodes.count,
              hourly.time.count == hourly.isDay.count else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let dayStart = calendar.startOfDay(for: now)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let times = hourly.time.compactMap { $0.date(in: timezone) }
        guard times.count == hourly.time.count,
              zip(times, times.dropFirst()).allSatisfy({ $1.timeIntervalSince($0) == 3_600 }) else {
            return nil
        }

        func daylightTime(_ values: [ForecastTime?]?) -> Date? {
            guard let values, values.indices.contains(dailyIndex),
                  let date = values[dailyIndex]?.date(in: timezone),
                  date >= dayStart, date < dayEnd else { return nil }
            return date
        }
        let sunrise = daylightTime(response.daily.sunrise)
        let sunset = daylightTime(response.daily.sunset)

        var runs: [Run] = []
        for index in times.indices {
            let start = max(dayStart, times[index])
            let end = min(dayEnd, times[index].addingTimeInterval(3_600))
            guard start < end else { continue }
            let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
            let category = category(
                code: hourly.weatherCodes[index], isDay: hourly.isDay[index],
                time: midpoint, sunrise: sunrise, sunset: sunset
            )
            if let last = runs.last, last.end == start, last.categories == [category] {
                runs[runs.count - 1].end = end
            } else {
                runs.append(Run(start: start, end: end, categories: [category]))
            }
        }
        guard runs.first?.start == dayStart, runs.last?.end == dayEnd,
              zip(runs, runs.dropFirst()).allSatisfy({ $0.end == $1.start }) else { return nil }

        // Combine the least disruptive neighbouring periods, retaining their actual
        // categories. Mixed periods are explicitly labelled, never called all-sunny.
        while runs.count > 6 {
            let index = (0..<(runs.count - 1)).min { mergeCost(runs[$0], runs[$0 + 1]) < mergeCost(runs[$1], runs[$1 + 1]) }!
            let next = runs.remove(at: index + 1)
            runs[index].end = next.end
            for category in next.categories where !runs[index].categories.contains(category) {
                runs[index].categories.append(category)
            }
        }

        let hourFormatter = DateFormatter()
        hourFormatter.locale = Locale(identifier: "en_US_POSIX")
        hourFormatter.timeZone = timezone
        hourFormatter.dateFormat = "HH"
        let detailedFormatter = DateFormatter()
        detailedFormatter.locale = Locale(identifier: "en_US_POSIX")
        detailedFormatter.timeZone = timezone
        detailedFormatter.dateFormat = "HH:mm z"
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = timezone
        dayFormatter.dateFormat = "d MMM"

        let blocks = runs.map { run in
            // Some time zones have half-hour DST transitions. Preserve those minutes.
            let hasMinutes = calendar.component(.minute, from: run.start) != 0
                || calendar.component(.minute, from: run.end) != 0
            hourFormatter.dateFormat = hasMinutes ? "HH:mm" : "HH"
            let start = hourFormatter.string(from: run.start)
            let end = run.end == dayEnd ? (hasMinutes ? "24:00" : "24") : hourFormatter.string(from: run.end)
            let repeatedHour = start == end && timezone.secondsFromGMT(for: run.start) != timezone.secondsFromGMT(for: run.end)
            let timeLabel = repeatedHour
                ? "\(detailedFormatter.string(from: run.start))–\(detailedFormatter.string(from: run.end))"
                : "\(start)–\(end)"
            return DayWeatherBlock(
                start: run.start, end: run.end, timeLabel: timeLabel,
                accessibleTimeLabel: "\(detailedFormatter.string(from: run.start)) to \(detailedFormatter.string(from: run.end))",
                categories: run.categories
            )
        }
        return DayTimeline(dateLabel: dayFormatter.string(from: dayStart), timezone: timezone.identifier, blocks: blocks)
    }

    private static func mergeCost(_ left: Run, _ right: Run) -> Double {
        let leftPriority = left.categories.map(\.priority).max() ?? 0
        let rightPriority = right.categories.map(\.priority).max() ?? 0
        let eventPenalty = leftPriority != rightPriority ? Double(max(leftPriority, rightPriority)) * 86_400 : 0
        let lightPenalty = left.categories.contains(.night) != right.categories.contains(.night) ? 43_200.0 : 0
        return right.end.timeIntervalSince(left.start) + eventPenalty + lightPenalty
    }

    private static func category(code: Int?, isDay: Int?, time: Date, sunrise: Date?, sunset: Date?) -> DayWeatherCategory {
        guard let code, let isDay, isDay == 0 || isDay == 1 else { return .unknown }
        let night = isDay == 0
        switch code {
        case 45, 48: return night ? .nightFog : .fog
        case 51, 53, 55: return night ? .nightDrizzle : .drizzle
        case 56, 57, 66, 67: return night ? .nightIce : .ice
        case 61, 63, 65, 80...82: return night ? .nightRain : .rain
        case 71, 73, 75, 77, 85, 86: return night ? .nightSnow : .snow
        case 95, 96, 99: return night ? .nightStorms : .storms
        case 0...3: break
        default: return .unknown
        }

        // These are hourly light-transition summaries, not exact astronomical
        // twilight boundaries. Wet weather and fog always take precedence above.
        if let sunrise, abs(time.timeIntervalSince(sunrise)) < 1_800 { return .dawn }
        if let sunset {
            let fromSunset = time.timeIntervalSince(sunset)
            if (-3_600..<0).contains(fromSunset), !night { return .lowLight }
            if (0..<1_800).contains(fromSunset) { return .dusk }
        }
        if night { return .night }
        switch code {
        case 0, 1: return .sunny
        case 2: return .partlyCloudy
        default: return .cloudy
        }
    }
}
