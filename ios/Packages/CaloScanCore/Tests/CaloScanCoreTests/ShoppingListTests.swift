import XCTest
@testable import CaloScanCore

final class ShoppingListTests: XCTestCase {

    func testCategoryGuess() {
        XCTAssertEqual(ShoppingCategory.guess(for: "Mele golden"), .produce)
        XCTAssertEqual(ShoppingCategory.guess(for: "Petto di pollo"), .meatFish)
        XCTAssertEqual(ShoppingCategory.guess(for: "Yogurt greco"), .dairyEggs)
        XCTAssertEqual(ShoppingCategory.guess(for: "Pasta integrale"), .pantry)
        XCTAssertEqual(ShoppingCategory.guess(for: "Detersivo"), .other)
    }

    func testSanitizedInput() {
        XCTAssertNil(ShoppingItem.sanitized(name: "   ", quantity: nil))
        let r = ShoppingItem.sanitized(name: "  latte   parzialmente scremato ", quantity: "  ")
        XCTAssertEqual(r?.0, "latte parzialmente scremato")
        XCTAssertNil(r?.1)
    }

    func testItemsFromPlanSumGramsAcrossTheWeek() {
        let start = ISO8601DateFormatter().date(from: "2026-11-23T10:00:00Z")!   // lunedì
        let plan = ProfessionalPlan(
            professional: .dietitian, calorieTarget: 1800, startDate: start, confirmedAt: start,
            mealPlan: [PlannedDay(weekday: nil, meals: [
                PlannedMeal(type: .breakfast, foods: [PlannedFood(name: "Yogurt greco", grams: 120)]),
                PlannedMeal(type: .lunch, foods: [PlannedFood(name: "Pasta integrale", grams: 80),
                                                  PlannedFood(name: "yogurt greco", grams: 30)]),
            ])])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let items = ShoppingListBuilder.items(from: plan, startingAt: start, days: 3, calendar: cal)
        XCTAssertEqual(items.map(\.name), ["Yogurt greco", "Pasta integrale"])
        XCTAssertEqual(items.map(\.quantity), ["450 g", "240 g"])
        XCTAssertTrue(items.allSatisfy { $0.source == .plan })
    }

    func testMergeSkipsDuplicates() {
        let list = [ShoppingItem(name: "Mele"), ShoppingItem(name: "Pane", isChecked: true)]
        let merged = ShoppingListBuilder.merge([ShoppingItem(name: "mele", quantity: "1 kg"), ShoppingItem(name: "Pane")], into: list)
        XCTAssertEqual(merged.count, 3)                  // "Pane" già preso: si aggiunge di nuovo
        XCTAssertEqual(merged[0].quantity, "1 kg")       // "Mele" non duplicata, quantità completata
    }
}
