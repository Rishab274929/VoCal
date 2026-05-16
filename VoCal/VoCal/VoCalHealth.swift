//
//  VoCalHealth.swift
//  VoCal
//
//  HealthKit wrapper. Writes dietary calories + macros + body metrics on
//  save; reads steps + active energy to inform the daily target nudge.
//  Gracefully no-ops if HealthKit is unavailable or permissions denied.
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

    @Published private(set) var isAuthorized = false

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
    func requestAuthorization() async {
        guard let store else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            isAuthorized = false
        }
    }

    /// Write a meal's calories + macros to HealthKit. No-ops if not authorized.
    func write(meal: MealEntry) async {
        guard let store, isAuthorized else { return }

        var samples: [HKQuantitySample] = []
        let start = meal.loggedAt
        let end = meal.loggedAt

        if let t = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            let q = HKQuantity(unit: .kilocalorie(), doubleValue: Double(meal.calories))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryProtein) {
            let q = HKQuantity(unit: .gram(), doubleValue: Double(meal.protein))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            let q = HKQuantity(unit: .gram(), doubleValue: Double(meal.carbs))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end))
        }
        if let t = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal) {
            let q = HKQuantity(unit: .gram(), doubleValue: Double(meal.fat))
            samples.append(HKQuantitySample(type: t, quantity: q, start: start, end: end))
        }

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    /// Write a body metric (weight + body fat %) to HealthKit.
    func write(bodyMetric m: BodyMetric) async {
        guard let store, isAuthorized else { return }
        var samples: [HKQuantitySample] = []
        let date = m.measuredAt

        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            let q = HKQuantity(unit: .pound(), doubleValue: m.weightLbs)
            samples.append(HKQuantitySample(type: t, quantity: q, start: date, end: date))
        }
        if let bf = m.bodyFatPct, let t = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) {
            let q = HKQuantity(unit: .percent(), doubleValue: bf / 100.0)
            samples.append(HKQuantitySample(type: t, quantity: q, start: date, end: date))
        }

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    /// Read today's active energy burned (kcal). Returns 0 if unavailable.
    func todayActiveEnergyKcal() async -> Double {
        guard let store, isAuthorized,
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
        guard let store, isAuthorized,
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
