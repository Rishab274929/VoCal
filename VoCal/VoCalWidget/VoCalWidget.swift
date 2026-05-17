//
//  VoCalWidget.swift
//  VoCalWidget
//
//  Home Screen widget. Reads today's calorie + protein snapshot the iOS app
//  publishes to the App Group container via `WidgetBridge` and renders a
//  small calorie ring + macro line. Keep the snapshot shape in sync with
//  `WidgetBridge.WidgetSnapshot` on the iOS side.
//

import WidgetKit
import SwiftUI

private let appGroupSuite = "group.com.EricSpencer.VoCal"
private let snapshotKey = "VoCalDailySnapshot.v1"

struct WidgetSnapshot: Codable {
    var caloriesEaten: Int = 0
    var calorieGoal: Int = 2000
    var proteinEaten: Int = 0
    var proteinGoal: Int = 150
}

struct VoCalEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    typealias Entry = VoCalEntry

    func placeholder(in context: Context) -> VoCalEntry {
        VoCalEntry(date: Date(), snapshot: WidgetSnapshot(caloriesEaten: 1200))
    }

    func getSnapshot(in context: Context, completion: @escaping (VoCalEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VoCalEntry>) -> Void) {
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [loadEntry()], policy: .after(refresh)))
    }

    private func loadEntry() -> VoCalEntry {
        let snap: WidgetSnapshot = {
            guard let data = UserDefaults(suiteName: appGroupSuite)?.data(forKey: snapshotKey),
                  let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
                return WidgetSnapshot()
            }
            return decoded
        }()
        return VoCalEntry(date: Date(), snapshot: snap)
    }
}

struct VoCalWidgetEntryView: View {
    let entry: VoCalEntry

    private var caloriePct: Double {
        guard entry.snapshot.calorieGoal > 0 else { return 0 }
        return min(Double(entry.snapshot.caloriesEaten) / Double(entry.snapshot.calorieGoal), 1)
    }

    private var proteinPct: Double {
        guard entry.snapshot.proteinGoal > 0 else { return 0 }
        return min(Double(entry.snapshot.proteinEaten) / Double(entry.snapshot.proteinGoal), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("VoCal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(entry.snapshot.caloriesEaten)")
                .font(.title2.bold())
                .minimumScaleFactor(0.7)
            Text("of \(entry.snapshot.calorieGoal) cal")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: caloriePct)
                .progressViewStyle(.linear)
                .tint(.primary)
            HStack(spacing: 4) {
                Text("Protein")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(entry.snapshot.proteinEaten)/\(entry.snapshot.proteinGoal)g")
                    .font(.caption2.monospacedDigit())
            }
        }
        .padding(.vertical, 2)
        .containerBackground(.background, for: .widget)
    }
}

struct VoCalWidget: Widget {
    let kind: String = "VoCalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            VoCalWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("VoCal")
        .description("Today's calorie and protein progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    VoCalWidget()
} timeline: {
    VoCalEntry(date: .now, snapshot: WidgetSnapshot(caloriesEaten: 1200, calorieGoal: 2000, proteinEaten: 75, proteinGoal: 150))
    VoCalEntry(date: .now, snapshot: WidgetSnapshot(caloriesEaten: 1850, calorieGoal: 2000, proteinEaten: 130, proteinGoal: 150))
}
