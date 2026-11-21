import XCTest
@testable import CaloScanCore

final class StatsTests: XCTestCase {
    private let food = FoodItem(name: "Test", per100g: Nutrients(kcal: 100, proteinG: 10, carbsG: 10, fatG: 2), source: .custom)

    private func day(_ offset: Int, kcal: Double) -> DayLog {
        let date = Calendar.current.date(byAdding: .day, value: offset, to: .now)!
        let meal = Meal(type: .lunch, loggedAt: date, items: [MealItem(food: food, grams: kcal)], source: .manual)
        return DayLog(day: date, meals: [meal])
    }

    func testSummarizeIgnoresEmptyDays() {
        let empty = DayLog(day: .now, meals: [])
        let stats = NutritionStats.summarize([day(0, kcal: 2000), day(1, kcal: 2500), day(2, kcal: 1500), empty],
                                             calorieTarget: 2000)
        XCTAssertEqual(stats.loggedDays, 3)
        XCTAssertEqual(stats.average.kcal, 2000, accuracy: 0.001)
        XCTAssertEqual(stats.daysOnTarget, 1)
        XCTAssertEqual(stats.daysOver, 1)
        XCTAssertEqual(stats.daysUnder, 1)
    }

    func testMealItemGramsClamped() {
        XCTAssertEqual(MealItem(food: food, grams: -5).grams, 1)
    }

    func testWeightProgress() {
        let entries = [WeightEntry(date: .distantPast, weightKg: 90), WeightEntry(date: .now, weightKg: 85)]
        let p = WeightProgress(entries: entries, goal: 80)!
        XCTAssertEqual(p.change, -5)
        XCTAssertEqual(p.fractionToGoal!, 0.5, accuracy: 0.001)
    }

    func testConfidenceBuckets() {
        XCTAssertEqual(Confidence(score: 0.3), .low)
        XCTAssertEqual(Confidence(score: 0.7), .medium)
        XCTAssertEqual(Confidence(score: 0.9), .high)
    }
}
