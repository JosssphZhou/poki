import Foundation
import HealthKit
import PokiCore

/// Steps from HealthKit. Read permission only: Poki never writes health data. An authorization call
/// that succeeds does not prove the owner allowed reading, so an empty statistics answer is reported
/// as an empty result, not as a zero.
enum HealthTools {
    static let specs: [ToolSpec] = [
        .make("health_steps",
              "Count the owner's steps with HealthKit. range is today or week (the calendar's week, from its first weekday to now); or give start and end dates. Returns the total and the range. An empty answer can mean no records or limited read access.",
              [
                "range": ["type": "string", "enum": ["today", "week"]],
                "start": ["type": "string", "description": "ISO 8601 date or yyyy-MM-dd HH:mm, local time."],
                "end": ["type": "string", "description": "ISO 8601 date or yyyy-MM-dd HH:mm, local time."],
              ], []),
    ]

    @MainActor private static let store = HKHealthStore()

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        let (start, end): (Date, Date)
        if let startDate = args.date("start") {
            let endDate = args.date("end") ?? Date()
            guard endDate > startDate else { return NativeToolAnswer.invalid("end must be after start; nothing was read") }
            // A bare yyyy-MM-dd end includes that local day.
            let endOfDay = args.string("end")?.contains(":") == false ? NativeDate.day(containing: endDate).1 : endDate
            (start, end) = (startDate, endOfDay)
        } else {
            switch (args.string("range") ?? "today").lowercased() {
            case "week":
                (start, end) = NativeDate.week()
            default:
                (start, end) = NativeDate.day(containing: Date())
            }
        }
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return NativeToolAnswer.unavailable("HealthKit is not available on this device")
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType])
        } catch {
            return NativeToolAnswer.permission("Health access could not be requested: \(error.localizedDescription). Allow Steps for Poki in Settings › Privacy & Security › Health. Nothing was read.")
        }
        let total: Double
        do {
            total = try await sum(stepType, from: start, to: end)
        } catch {
            return NativeToolAnswer.failed("HealthKit did not return steps: \(error.localizedDescription)")
        }
        guard total > 0 else {
            return NativeToolAnswer.empty("no step records between \(NativeDate.display(start)) and \(NativeDate.display(end)). Read access may be limited or the iPhone may have no step data for this range.")
        }
        let count = Int(total.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let text = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return NativeToolAnswer.ok("steps: \(text)\nrange: \(NativeDate.display(start)) – \(NativeDate.display(end))\nsource: HealthKit on this iPhone")
    }

    @MainActor private static func sum(_ type: HKQuantityType, from start: Date, to end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let sum = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    continuation.resume(returning: sum)
                }
            }
            store.execute(query)
        }
    }
}
