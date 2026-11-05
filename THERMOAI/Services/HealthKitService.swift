//
//  HealthKitService.swift
//  THERMOAI — Services
//
//  Purpose: Optional Apple Health integration.
//    Reads:  body mass, height, body fat %, active energy burned.
//    Writes: dietary energy & macros (per food entry), body mass.
//  Dependencies: HealthKit
//

import Foundation
import HealthKit

protocol HealthServicing: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async throws
    func latestBodyMassKg() async throws -> Double?
    func latestHeightCm() async throws -> Double?
    func latestBodyFatPercent() async throws -> Double?
    func activeEnergyKcal(on day: Date) async throws -> Double
    func saveFood(name: String, date: Date, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, entryID: UUID) async throws
    func saveBodyMass(kg: Double, date: Date) async throws
}

final class HealthKitService: HealthServicing, @unchecked Sendable {
    // HKHealthStore is thread-safe; @unchecked is required because it is not annotated Sendable.
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKQuantityType(.height), HKQuantityType(.bodyFatPercentage), HKQuantityType(.activeEnergyBurned)]
    }

    /// Note: the `.food` correlation type must NOT be requested (HealthKit raises an
    /// exception); authorising its member quantity types is sufficient to save it.
    private var writeTypes: Set<HKSampleType> {
        [HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein), HKQuantityType(.dietaryCarbohydrates),
         HKQuantityType(.dietaryFatTotal), HKQuantityType(.bodyMass)]
    }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
    }

    // MARK: Reads

    func latestBodyMassKg() async throws -> Double? {
        try await latest(.bodyMass, unit: .gramUnit(with: .kilo))
    }

    func latestHeightCm() async throws -> Double? {
        try await latest(.height, unit: .meterUnit(with: .centi))
    }

    func latestBodyFatPercent() async throws -> Double? {
        try await latest(.bodyFatPercentage, unit: .percent()).map { $0 * 100 }
    }

    func activeEnergyKcal(on day: Date) async throws -> Double {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            predicate: HKQuery.predicateForSamples(withStart: start, end: end)
        )
        let descriptor = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        let result = try await descriptor.result(for: store)
        return result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }

    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        return try await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    // MARK: Writes

    func saveFood(name: String, date: Date, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, entryID: UUID) async throws {
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: name,
            HKMetadataKeySyncIdentifier: entryID.uuidString,
            HKMetadataKeySyncVersion: Int(Date().timeIntervalSince1970),
        ]
        func sample(_ id: HKQuantityTypeIdentifier, _ value: Double, _ unit: HKUnit) -> HKQuantitySample {
            HKQuantitySample(type: HKQuantityType(id), quantity: HKQuantity(unit: unit, doubleValue: value),
                             start: date, end: date, metadata: metadata)
        }
        let samples: Set<HKSample> = [
            sample(.dietaryEnergyConsumed, calories, .kilocalorie()),
            sample(.dietaryProtein, proteinG, .gram()),
            sample(.dietaryCarbohydrates, carbsG, .gram()),
            sample(.dietaryFatTotal, fatG, .gram()),
        ]
        let food = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date, objects: samples, metadata: metadata)
        try await store.save(food)
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass),
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                                      start: date, end: date)
        try await store.save(sample)
    }
}
