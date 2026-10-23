import Foundation

/// Support status of a Python minor version, from the release schedule on devguide.python.org/versions
/// (checked 2026-10-23). Update this table when new versions ship.
public enum PythonLifecycle {
    public enum Status: Equatable, Sendable {
        /// Support ended (no more security fixes).
        case endOfLife(String)
        /// Still supported, but support ends within a year.
        case endingSoon(String)
        case supported(String)
    }
    
    /// Minor version -> end-of-life month ("yyyy-MM") or exact date ("yyyy-MM-dd").
    private static let endOfLifeDates: [String: String] = [
        "3.8": "2024-10-07",
        "3.9": "2025-10-31",
        "3.10": "2026-10-01",
        "3.11": "2027-10",
        "3.12": "2028-10",
        "3.13": "2029-10",
        "3.14": "2030-10",
        "3.15": "2031-10"
    ]
    
    /// Version DevKeeper recommends installing.
    public static let recommendedMinor = "3.13"
    
    public static func status(forMinor minor: String, now: Date = Date()) -> Status {
        guard let raw = endOfLifeDates[minor] else {
            // Anything older than the table is finished; anything newer is too new to have a date yet.
            return minor.compare("3.8", options: .numeric) != .orderedDescending
                ? .endOfLife("已結束")
                : .supported("支援中")
        }
        let end = endDate(raw)
        if end <= now { return .endOfLife(raw) }
        let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now
        return end <= oneYear ? .endingSoon(raw) : .supported(raw)
    }
    
    public static func isEndOfLife(minor: String, now: Date = Date()) -> Bool {
        if case .endOfLife = status(forMinor: minor, now: now) { return true }
        return false
    }
    
    private static func endDate(_ raw: String) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return .distantFuture }
        var comps = DateComponents(year: parts[0], month: parts[1], day: parts.count > 2 ? parts[2] : nil)
        if parts.count == 2 {
            // Month only: treat the end of that month as the deadline.
            comps.day = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: parts[0], month: parts[1])) ?? Date())?.count ?? 28
        }
        return calendar.date(from: comps) ?? .distantFuture
    }
}

extension PythonInterpreter {
    public var lifecycle: PythonLifecycle.Status { PythonLifecycle.status(forMinor: minorVersion) }
    public var isEndOfLife: Bool { PythonLifecycle.isEndOfLife(minor: minorVersion) }
}
