//
//  VoCalHealth.swift
//  VoCal
//
//  HealthKit wrapper. Writes dietary calories + macros + body metrics on
//  save; reads steps + active energy to inform the daily target nudge.
//  Gracefully no-ops if HealthKit is unavailable or permissions denied.
//
//  Authorization semantics (Apple's design, not ours):
//    - `requestAuthorization` does NOT throw on user denial — it throws only
//      on transport-level failure. A user tapping "Don't Allow" returns a
//      perfectly successful Void. So we cannot infer authorization from
//      a non-throwing call.
//    - For WRITE types you cannot read `authorizationStatus(for:)` to learn
//      whether the user granted write — Apple deliberately hides that to
//      prevent fingerprinting which permissions were denied. The only
//      reliable signal is whether a sample save actually succeeds.
//    - For READ types you cannot read status either; same anti-fingerprint
//      design. A failed read just returns zero samples.
//
//  Practical upshot: `isAuthorized` here means "we asked, and the prompt
//  resolved without a transport error." Actual permission is verified
//  per-save by catching the save error. Write paths therefore use `try await`
//  + log on failure rather than the prior `try?` swallow.
//

import Foundation
import Combine
import HealthKit

@MainActor
final class VoCalHealth: ObservableObject {
    static let shared = VoCalHealth()

    private let store: HKHealthStore? = {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return HKHealthStore()
    }()

    /// "Did we successfully ASK?" — not "did the user grant?". See file header.
    @Published private(set) var didRequestAuthorization = false

    /// Last write error message, exposed for diagnostics. Cleared on next
    /// successful save.
    @Published private(set) var lastWriteError: String?

    /// Metadata key we stamp on every sample we write, so we can identify
    /// (and the user can identify) which Health samples came from VoCal.
    /// Combined with `HKMetadataKeyExternalUUID = meal.id` this gives
    /// Apple Health enough to dedupe a retried save on its side.
    private static let metaSourceKey  = "vocal.source"
    private static let metaMealNameKey = "vocal.mealName"

    private var writeTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryProtein)        { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)  { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)       { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass)              { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)     { s.insert(t) }
        return s
    }

    private var readTypes: Set<HKObjectType> {
        var s = Set<HKObjectType>()
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount)         { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { s.insert(t) }
        return s
    }

    /// Request both read + write permission. Safe to call repeatedly.
    /// Returns true if the system prompt resolved without error — NOT
    /// a guarantee the user granted (see file header).
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard let store else { return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            didRequestAuthorization = true
            return true
        } catch {
            didRequestAuthorization = false
            lastWriteError = "Health permission request failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Whether we've completed the auth prompt at least once. Used by
    /// callers (notably `AppModel.addMeal`'s fire-and-forget HK write)
    /// as a cheap gate to avoid trying a save before the prompt is done.
    var isAuthorizedRequested: Bool { didRequestAuthorization }

    /// Write a meal's calories + macros to HealthKit. Triggers the system
    /// authorization prompt on first call (we intentionally avoid prompting
    /// at app launch — see `VoCalApp.swift`). If the user denies, the
    /// underlying save throws — we surface that via `lastWriteError` rather
    /// than crash. Subsequent calls re-use the prior auth state.
    func write(meal: MealEntry) async {
        guard let store else { return }
        // Lazy auth: the first meal save is the contextual moment for HK
        // permission. If we've never asked, ask now and continue regardless
        // of the user's response (a denial just means the save below will
        // throw, which is already handled).
        if !didRequestAuthorization {
            _ = await requestAuthorization()
        }
        guard didRequestAuthorization else { return }

        var samples: [HKQuantitySample] = []
        let start = meal.loggedAt
        let end = meal.loggedAt

        // Stamp every sample with `HKMetadataKeyExternalUUID = meal.id` so
        // if AppModel.addMeal is retried (network re-foreground, app resume
        // mid-write, etc.) HealthKit dedupes on its side. Without this, the
        // 2-second in-process AppModel dedupe in Item.swift is the only
        // defense — but that loses to longer-window retries or to a fresh
        // app launch happening between save attempts.
        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: meal.id.uuidString,
            Self.metaSourceKey: "VoCal",
            Self.metaMealNameKey: meal.name
        ]

        if let t = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let q = HKQuantity(unit: .kilocalorie(), doubleValue: Double(meal.calories))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end, metadata: metadata))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            let q = HKQuantity(unit: .gram(), doubleValue: Double(meal.protein))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end, metadata: metadata))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let q = HKQuantity(unit: .gram(), doubleValue: Double(meal.carbs))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end, metadata: metadata))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            let q = HKQuantity(unit: .gram(), doubleValue: Double(meal.fat))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end, metadata: metadata))
        }

        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            lastWriteError = nil
        } catch {
            // Save can throw for: not-yet-authorized, user-denied write,
            // sample-validation failure, or the device's Health DB being
            // unavailable. We log + surface but never crash the meal-save
            // flow that fired this off.
            lastWriteError = "Health save failed: \(error.localizedDescription)"
            #if DEBUG
            print("[VoCalHealth] save(meal:) failed: \(error)")
            #endif
        }
    }

    /// Write a body metric (weight + body fat %) to HealthKit. Triggers the
    /// system authorization prompt on first call — same lazy-auth pattern as
    /// `write(meal:)` so the prompt arrives at a contextual moment rather
    /// than at app launch.
    func write(bodyMetric m: BodyMetric) async {
        guard let store else { return }
        if !didRequestAuthorization {
            _ = await requestAuthorization()
        }
        guard didRequestAuthorization else { return }
        var samples: [HKQuantitySample] = []
        let date = m.measuredAt

        let metadata: [String: Any] = [
            HKMetadataKeyExternalUUID: m.id.uuidString,
            Self.metaSourceKey: "VoCal"
        ]

        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            let q = HKQuantity(unit: .pound(), doubleValue: m.weightLbs)
            samples.append(HKQuantitySample(type: t, quantity: q, start: date, end: date, metadata: metadata))
        }
        if let bf = m.bodyFatPct, let t = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            let q = HKQuantity(unit: .percent(), doubleValue: bf / 100.0)
            samples.append(HKQuantitySample(type: t, quantity: q, start: date, end: date, metadata: metadata))
        }

        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
            lastWriteError = nil
        } catch {
            lastWriteError = "Health save failed: \(error.localizedDescription)"
            #if DEBUG
            print("[VoCalHealth] save(bodyMetric:) failed: \(error)")
            #endif
        }
    }

    /// Delete the HealthKit samples we wrote for a given meal. Called when
    /// the user removes the meal in-app so Apple Health stays in sync.
    /// Best-effort: no-op on unauthorized / unavailable / no-match.
    func delete(meal: MealEntry) async {
        guard let store, didRequestAuthorization else { return }
        let types: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal
        ]
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: meal.id.uuidString
        )
        for id in types {
            guard let type = HKObjectType.quantityType(forIdentifier: id) else { continue }
            do {
                try await store.deleteObjects(of: type, predicate: predicate)
            } catch {
                #if DEBUG
                print("[VoCalHealth] delete(meal:) failed for \(id): \(error)")
                #endif
            }
        }
    }

    /// Read today's active energy burned (kcal). Returns 0 if unavailable.
    func todayActiveEnergyKcal() async -> Double {
        guard let store, didRequestAuthorization,
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [.strictStartDate])

        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let kcal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                cont.resume(returning: kcal)
            }
            store.execute(q)
        }
    }

    /// Read today's step count. Returns 0 if unavailable.
    func todaySteps() async -> Int {
        guard let store, didRequestAuthorization,
              let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now, options: [.strictStartDate])

        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let count = stats?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                cont.resume(returning: Int(count))
            }
            store.execute(q)
        }
    }
}
