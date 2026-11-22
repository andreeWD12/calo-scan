import XCTest
@testable import CaloScanCore

/// Stessi casi dei test "piano" e "descrizione" in `supabase/functions/_shared/nutrition.test.ts`.
final class ProfessionalPlanTests: XCTestCase {

    private let start = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!

    private func plan(kcal: Int = 1600, p: Int? = nil, c: Int? = nil, f: Int? = nil, review: Date? = nil) -> ProfessionalPlan {
        ProfessionalPlan(professional: .doctor, calorieTarget: kcal, proteinG: p, carbsG: c, fatG: f,
                         startDate: start, reviewDate: review, confirmedAt: start)
    }

    func testValidPlan() {
        XCTAssertEqual(plan().validate(), [])
        XCTAssertEqual(plan(kcal: 1000).validate(), [])
    }

    func testCaloriesOutOfRange() {
        XCTAssertEqual(plan(kcal: 700).validate(), [.caloriesOutOfRange])
        XCTAssertEqual(plan(kcal: 6500).validate(), [.caloriesOutOfRange])
    }

    func testMacrosMustMatchCalories() {
        XCTAssertEqual(plan(p: 100, c: 180, f: 53).validate(), [])
        XCTAssertEqual(plan(p: 200, c: 300, f: 100).validate(), [.macrosDoNotMatchCalories])
    }

    func testReviewBeforeStart() {
        let before = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
        XCTAssertEqual(plan(review: before).validate(), [.reviewBeforeStart])
    }

    func testMissingMacrosFollowComputedShares() {
        let base = DailyTargets(bmr: 1400, tdee: 2000, calorieTarget: 2000, proteinG: 125, carbsG: 225, fatG: 67,
                                isAdjustedForSafety: false)
        XCTAssertEqual(plan().dailyTargets(fallback: base),
                       DailyTargets(bmr: 1400, tdee: 2000, calorieTarget: 1600, proteinG: 100, carbsG: 179, fatG: 54,
                                    isAdjustedForSafety: false))
        XCTAssertEqual(plan(p: 90).dailyTargets(fallback: nil),
                       DailyTargets(bmr: 0, tdee: 0, calorieTarget: 1600, proteinG: 90, carbsG: 191, fatG: 53,
                                    isAdjustedForSafety: false))
    }

    func testBelowAppFloorIsFlagged() {
        XCTAssertTrue(plan(kcal: 1000).isBelowAppFloor(for: .female))
        XCTAssertFalse(plan(kcal: 1600).isBelowAppFloor(for: .male))
    }

    func testFoodDescriptionSanitizing() {
        XCTAssertEqual(FoodDescription.sanitize("  pasta al pomodoro\n\t 80 g  "), "pasta al pomodoro 80 g")
        XCTAssertNil(FoodDescription.sanitize("ok"))
        XCTAssertNil(FoodDescription.sanitize("123 456"))
        XCTAssertNil(FoodDescription.sanitize(String(repeating: "a", count: 501)))
    }
}
