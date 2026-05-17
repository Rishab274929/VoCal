//
//  WidgetBridge.swift
//  VoCal
//
//  Mirror today's calorie + protein totals into the App Group UserDefaults
//  suite that the VoCalWidget reads, and kick the widget's timeline so the
//  home-screen tile refreshes immediately after a meal mutation.
//
//  This is intentionally tiny. The widget consumes a flat
//  `{caloriesEaten, calorieGoal, proteinEaten, proteinGoal}` payload — keep
//  the schema compact so the widget process doesn't have to decode the full
//  `DailyMacrosSnapshot` (which carries date + every macro and would force
//  the widget to be aware of the iOS app's larger model).
//
//  Why a separate suite vs. `UserDefaults.standard`: widget extensions run
//  in their own sandbox and can't see the host app's standard defaults. The
//  App Group "group.com.EricSpencer.VoCal" is the shared container both
//  bundles can read/write via `UserDefaults(suiteName:)`.
//

import Foundation
import WidgetKit

enum WidgetBridge {
    static let suiteName = "group.com.EricSpencer.VoCal"
    static let snapshotKey = "VoCalDailySnapshot.v1"
    static let widgetKind = "VoCalWidget"

    /// Compact today snapshot the widget consumes. Keep this struct in sync
    /// with the widget-side decoder (see `VoCalWidget/VoCalWidget.swift`).
    private struct WidgetSnapshot: Codable {
        var caloriesEaten: Int
        var calorieGoal: Int
        var proteinEaten: Int
        var proteinGoal: Int
    }

    /// Write today's totals to the shared suite and refresh the widget
    /// timeline. Best-effort — never throws; widget-refresh failures are
    /// silent because they're harmless (the OS will refresh later anyway).
    nonisolated static func publish(from totals: DailyTotals) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let snap = WidgetSnapshot(
            caloriesEaten: totals.caloriesEaten,
            calorieGoal: totals.calorieGoal,
            proteinEaten: totals.proteinEaten,
            proteinGoal: totals.proteinGoal
        )
        if let data = try? JSONEncoder().encode(snap) {
            defaults.set(data, forKey: snapshotKey)
        }
        // Refresh the widget. Cheap; the OS coalesces multiple calls.
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
