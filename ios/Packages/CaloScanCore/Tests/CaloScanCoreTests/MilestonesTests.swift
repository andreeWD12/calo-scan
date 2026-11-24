import XCTest
@testable import CaloScanCore

final class MilestonesTests: XCTestCase {
    private let targets = DailyTargets(bmr: 1400, tdee: 2000, calorieTarget: 2000, proteinG: 100, carbsG: 250, fatG: 65,
                                       isAdjustedForSafety: false)
    private let food = FoodItem(name: "Test", per100g: Nutrients(kcal: 100, proteinG: 5, carbsG: 12, fatG: 3), source: .custom)
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Rome")!; return c }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 21))! }

    private func day(_ daysAgo: Int, _ meals: [(MealType, Double)]) -> DayLog {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return DayLog(day: date, meals: meals.map { Meal(type: $0.0, loggedAt: date, items: [MealItem(food: food, grams: $0.1)], source: .manual) })
    }

    func testDayOnTargetNeedsDinnerAndRange() {
        let full = day(0, [(.breakfast, 400), (.lunch, 800), (.dinner, 800)])
        let m = Milestones.afterMeal(logs: [full], targets: targets, goal: .loseWeight, now: now, calendar: calendar)
        XCTAssertTrue(m.contains(.dayOnTarget))
        XCTAssertTrue(m.contains(.proteinReached))
        XCTAssertTrue(m.contains(.allMainMeals))
        let under = day(0, [(.lunch, 600), (.dinner, 600)])
        XCTAssertFalse(Milestones.afterMeal(logs: [under], targets: targets, goal: .loseWeight, now: now, calendar: calendar).contains(.dayOnTarget),
                       "mai festeggiare un giorno sotto l'obiettivo")
        let noDinner = day(0, [(.lunch, 2000)])
        XCTAssertFalse(Milestones.afterMeal(logs: [noDinner], targets: targets, goal: .maintain, now: now, calendar: calendar).contains(.dayOnTarget))
        XCTAssertFalse(Milestones.afterMeal(logs: [full], targets: targets, goal: .trackOnly, now: now, calendar: calendar).contains(.dayOnTarget))
    }

    func testStreakSteps() {
        let logs = (0..<7).map { day($0, [(.lunch, 300)]) }
        XCTAssertTrue(Milestones.afterMeal(logs: logs, targets: nil, goal: nil, now: now, calendar: calendar).contains(.streak(7)))
        XCTAssertTrue(Milestone.streak(7).isCelebration)
        XCTAssertFalse(Milestone.streak(3).isCelebration)
        let five = (0..<5).map { day($0, [(.lunch, 300)]) }
        XCTAssertFalse(Milestones.afterMeal(logs: five, targets: nil, goal: nil, now: now, calendar: calendar).contains { if case .streak = $0 { true } else { false } })
    }

    func testFirstMealWelcomeBackOrHabitTip() {
        let back = Milestones.afterMeal(logs: [day(0, [(.breakfast, 300)]), day(6, [(.lunch, 300)])], targets: nil, goal: nil, now: now, calendar: calendar)
        XCTAssertEqual(back, [.welcomeBack])
        let regular = Milestones.afterMeal(logs: [day(0, [(.breakfast, 300)]), day(1, [(.lunch, 300)])], targets: nil, goal: nil, now: now, calendar: calendar)
        XCTAssertEqual(regular.count, 1)
        if case .habitTip(let i) = regular[0] { XCTAssertTrue((0..<Milestone.habitTipCount).contains(i)) } else { XCTFail() }
        XCTAssertTrue(Milestones.afterMeal(logs: [], targets: targets, goal: nil, now: now, calendar: calendar).isEmpty)
    }

    func testWeightMilestonesBothDirections() {
        func e(_ d: Int, _ w: Double) -> WeightEntry { WeightEntry(date: Date(timeIntervalSince1970: Double(d) * 86_400), weightKg: w) }
        XCTAssertEqual(Milestones.afterWeight(entries: [e(0, 90), e(10, 86), e(20, 84.8)], goal: 80), [.weightHalfway])
        XCTAssertEqual(Milestones.afterWeight(entries: [e(0, 90), e(10, 81), e(20, 79.9)], goal: 80), [.weightGoalReached])
        XCTAssertEqual(Milestones.afterWeight(entries: [e(0, 60), e(10, 64), e(20, 65)], goal: 65), [.weightGoalReached])
        XCTAssertEqual(Milestones.afterWeight(entries: [e(0, 90), e(10, 79), e(20, 78)], goal: 80), [], "già raggiunto: niente doppia festa")
        XCTAssertEqual(Milestones.afterWeight(entries: [e(0, 90)], goal: 80), [])
        XCTAssertEqual(Milestones.afterWeight(entries: [e(0, 90), e(10, 85)], goal: nil), [])
    }
}
