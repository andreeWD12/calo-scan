import XCTest
@testable import CaloScanCore

final class DailyTipsTests: XCTestCase {
    private let targets = DailyTargets(bmr: 1400, tdee: 2000, calorieTarget: 2000, proteinG: 100, carbsG: 250, fatG: 65,
                                       isAdjustedForSafety: false)
    private let food = FoodItem(name: "Test", per100g: Nutrients(kcal: 100, proteinG: 2, carbsG: 15, fatG: 3), source: .custom)
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Rome")!; return c }

    private func at(hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: hour))! }

    private func log(kcal: Double, daysAgo: Int = 0) -> DayLog {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: at(hour: 13))!
        return DayLog(day: date, meals: [Meal(type: .lunch, loggedAt: date, items: [MealItem(food: food, grams: kcal)], source: .manual)])
    }

    func testEmptyDayInvitesToLog() {
        let tips = DailyTips.make(today: DayLog(day: at(hour: 8), meals: []), recent: [], targets: targets, diet: nil,
                                  allergens: [], now: at(hour: 8), calendar: calendar)
        XCTAssertEqual(tips.count, 1)
        XCTAssertTrue(tips[0].text.contains("colazione"))
    }

    func testRemainingAndProteinSuggestionRespectAllergensAndDiet() {
        let tips = DailyTips.make(today: log(kcal: 1500), recent: [], targets: targets, diet: .vegetarian,
                                  allergens: [.eggs], now: at(hour: 18), calendar: calendar)
        XCTAssertTrue(tips[0].text.contains("500 kcal"))
        XCTAssertEqual(tips[1].tone, .suggestion)
        XCTAssertFalse(tips[1].text.contains("uova"))
        XCTAssertFalse(tips[1].text.contains("pesce"))
        XCTAssertTrue(tips[1].text.contains("legumi"))
    }

    func testOverTargetIsReassuringNeverRestrictive() {
        let tips = DailyTips.make(today: log(kcal: 2600), recent: [], targets: targets, diet: nil, allergens: [],
                                  now: at(hour: 21), calendar: calendar)
        XCTAssertTrue(tips[0].text.contains("Nessun problema"))
        XCTAssertFalse(tips.contains { $0.text.lowercased().contains("salta") || $0.text.lowercased().contains("digiun") })
    }

    func testConsistencyAndWeekAverage() {
        let recent = (1...6).map { log(kcal: 2000, daysAgo: $0) }
        let tips = DailyTips.make(today: log(kcal: 1950), recent: recent, targets: targets, diet: nil, allergens: [],
                                  now: at(hour: 10), calendar: calendar)
        XCTAssertLessThanOrEqual(tips.count, DailyTips.maxTips)
        XCTAssertTrue(tips.contains { $0.text.contains("6 degli ultimi 7") })
    }

    func testProteinIdeasVegan() {
        XCTAssertEqual(DailyTips.proteinIdeas(diet: .vegan, allergens: [.soy]), "legumi")
        XCTAssertEqual(DailyTips.proteinIdeas(diet: nil, allergens: []), "legumi, uova o pesce")
    }
}
