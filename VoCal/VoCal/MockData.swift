//
//  MockData.swift
//  VoCal
//
//  Demo seed data. Tuned for the killer-demo storyline so a judge
//  scrolling the app sees believable, restaurant-rich entries.
//

import Foundation

enum MockData {
    static let profile = UserProfile(
        displayName: "Eric",
        streakDays: 12,
        weightLbs: 168,
        heightInches: 70,
        dailyCalorieGoal: 2200,
        sex: "m",
        birthYear: 1995,
        entitlement: .free
    )

    static let today = DailyTotals(
        date: .now,
        calorieGoal: 2200,
        caloriesEaten: 1180,
        proteinGoal: 160,
        proteinEaten: 84,
        carbsGoal: 240,
        carbsEaten: 138,
        fatGoal: 70,
        fatEaten: 41
    )

    static let recentMeals: [MealEntry] = [
        MealEntry(
            name: "Chipotle Chicken Bowl",
            detail: "Double chicken, brown rice, black beans, 1× guac",
            calories: 1080, protein: 74, carbs: 78, fat: 42,
            loggedAt: at(hour: 13, minute: 06),
            slot: .lunch, source: .voice
        ),
        MealEntry(
            name: "Starbucks Iced Oatmilk Latte",
            detail: "Grande, oatmilk, no syrup",
            calories: 190, protein: 3, carbs: 24, fat: 8,
            loggedAt: at(hour: 10, minute: 22),
            slot: .breakfast, source: .voice
        ),
        MealEntry(
            name: "Greek yogurt + berries",
            detail: "Fage 2%, blueberries, honey, walnuts",
            calories: 320, protein: 22, carbs: 34, fat: 11,
            loggedAt: at(hour: 8, minute: 12),
            slot: .breakfast, source: .voice
        )
    ]

    /// LEAK WARNING — this is still being read from `HistoryView.pastDaysList`
    /// in production code (search for `MockData.historySummaries`), which
    /// means every shipping user sees fake history numbers in the "Recent
    /// days" section regardless of their actual log. Per commit `57909c5`
    /// this should be sourced from `AppModel.meals` aggregated by day; the
    /// fix lives in `HistoryView.swift` (out of scope for the
    /// data/persistence agent) so this constant stays here until that lands.
    /// Do NOT add `@available(deprecated)` — it would warn in the upstream
    /// HistoryView build and confuse the parallel-agent integration pass.
    static let historySummaries: [(date: Date, calories: Int, goal: Int)] = {
        let sample = [2080, 1890, 2210, 1750, 2340, 2020, 1660, 2150, 1980, 2280, 1820, 2090, 1940, 2050]
        return sample.enumerated().map { offset, eaten in
            let day = Calendar.current.date(byAdding: .day, value: -(offset + 1), to: .now) ?? .now
            return (day, eaten, 2200)
        }
    }()

    static let voicePrompts: [String] = [
        "log a medium fry from McDonald's",
        "grande iced oat latte from Starbucks",
        "Chipotle bowl, double chicken, brown rice, black beans, guac",
        "two scrambled eggs and a piece of toast",
        "a big bowl of pasta with red sauce"
    ]

    static let weightSeries: [Double] = [
        171.4, 171.0, 170.6, 170.2, 169.9, 169.6, 169.2,
        168.9, 168.7, 168.5, 168.2, 168.0
    ]

    static let bodyFatSeries: [Double] = [
        18.4, 18.2, 18.1, 17.9, 17.7, 17.6, 17.4, 17.2, 17.0
    ]

    static let bodyMetrics: [BodyMetric] = {
        let cal = Calendar.current
        return weightSeries.enumerated().reversed().map { idx, w in
            let bfIdx = bodyFatSeries.count - 1 - idx
            let bf = bfIdx >= 0 && bfIdx < bodyFatSeries.count ? bodyFatSeries[bfIdx] : nil
            let date = cal.date(byAdding: .day, value: -idx * 3, to: .now) ?? .now
            return BodyMetric(weightLbs: w, bodyFatPct: bf, confidence: 0.82, measuredAt: date)
        }
    }()

    static let coachIntro: [CoachMessage] = [
        CoachMessage(
            role: .assistant,
            content: "Morning. You're 1,020 kcal under and 76g of protein short. Want a high-protein lunch idea from a chain you usually order from?"
        )
    ]

    // MARK: helpers

    private static func at(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
