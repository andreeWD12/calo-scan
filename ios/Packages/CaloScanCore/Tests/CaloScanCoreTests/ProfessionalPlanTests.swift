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

    func testMealPlanValidation() {
        func day(_ weekday: Int?, grams: Double = 80) -> PlannedDay {
            PlannedDay(weekday: weekday, meals: [PlannedMeal(type: .lunch, foods: [PlannedFood(name: "Pasta integrale", grams: grams)])])
        }
        var p = plan()
        p.mealPlan = [day(nil), day(2)]
        XCTAssertEqual(p.validate(), [])
        p.mealPlan = [day(2), day(2)]
        XCTAssertEqual(p.validate(), [.mealPlanInvalid])
        p.mealPlan = [day(nil, grams: 0)]
        XCTAssertEqual(p.validate(), [.mealPlanInvalid])
        p.mealPlan = [day(9)]
        XCTAssertEqual(p.validate(), [.mealPlanInvalid])
    }

    func testPlannedMealsForDate() {
        let pasta = FoodItem(name: "Pasta", per100g: Nutrients(kcal: 350, proteinG: 12, carbsG: 72, fatG: 1.5), source: .usda)
        var p = plan()
        p.mealPlan = [
            PlannedDay(weekday: nil, meals: [PlannedMeal(type: .lunch, foods: [PlannedFood(name: "Pasta", grams: 80, food: pasta)])]),
            PlannedDay(weekday: 2, meals: [PlannedMeal(type: .lunch, foods: [PlannedFood(name: "Pasta", grams: 60, food: pasta),
                                                                            PlannedFood(name: "Verdure", grams: 200)])]),
        ]
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let monday = ISO8601DateFormatter().date(from: "2026-11-23T12:00:00Z")!   // lunedì → weekday 2
        let tuesday = ISO8601DateFormatter().date(from: "2026-11-24T12:00:00Z")!
        let mondayLunch = p.plannedMeal(.lunch, on: monday, calendar: cal)
        XCTAssertEqual(mondayLunch?.foods.count, 2)
        XCTAssertEqual(mondayLunch?.unmatchedCount, 1)
        XCTAssertEqual(mondayLunch?.mealItems().count, 1)
        XCTAssertEqual(mondayLunch?.totals.kcal ?? 0, 210, accuracy: 0.001)
        XCTAssertEqual(p.plannedMeal(.lunch, on: tuesday, calendar: cal)?.foods.first?.grams, 80)
        XCTAssertNil(p.plannedMeal(.dinner, on: tuesday, calendar: cal))
    }

    func testCheatMealSummary() {
        let pizza = FoodItem(name: "Pizza", per100g: Nutrients(kcal: 270, proteinG: 11, carbsG: 33, fatG: 10), source: .usda)
        let day = DayLog(day: start, meals: [
            Meal(type: .lunch, loggedAt: start, items: [MealItem(food: pizza, grams: 100)], source: .manual),
            Meal(type: .dinner, loggedAt: start, items: [MealItem(food: pizza, grams: 300)], source: .scan, isCheatMeal: true),
        ])
        let s = NutritionStats.cheatMeals([day])
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.kcal, 810, accuracy: 0.001)
        XCTAssertEqual(s.shareOfTotal, 0.75, accuracy: 0.001)
    }

    func testMealDecodesWithoutCheatFlag() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","type":"lunch","loggedAt":0,"items":[],"source":"manual"}"#
        let meal = try JSONDecoder().decode(Meal.self, from: Data(json.utf8))
        XCTAssertFalse(meal.isCheatMeal)
    }

    func testFoodDescriptionSanitizing() {
        XCTAssertEqual(FoodDescription.sanitize("  pasta al pomodoro\n\t 80 g  "), "pasta al pomodoro 80 g")
        XCTAssertNil(FoodDescription.sanitize("ok"))
        XCTAssertNil(FoodDescription.sanitize("123 456"))
        XCTAssertNil(FoodDescription.sanitize(String(repeating: "a", count: 501)))
    }

    func testRotationWeeks() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        cal.firstWeekday = 2   // lunedì, come in Italia
        let d = { (s: String) in ISO8601DateFormatter().date(from: s + "T12:00:00Z")! }
        let anchor = d("2026-11-22")   // domenica: settimana 1 = lun 16 – dom 22 novembre
        XCTAssertEqual(ProfessionalPlan.rotationWeek(on: d("2026-11-22"), anchor: anchor, weeks: 2, calendar: cal), 1)
        XCTAssertEqual(ProfessionalPlan.rotationWeek(on: d("2026-11-23"), anchor: anchor, weeks: 2, calendar: cal), 2)
        XCTAssertEqual(ProfessionalPlan.rotationWeek(on: d("2026-11-30"), anchor: anchor, weeks: 2, calendar: cal), 1)
        XCTAssertEqual(ProfessionalPlan.rotationWeek(on: d("2026-12-09"), anchor: anchor, weeks: 3, calendar: cal), 1)
        XCTAssertEqual(ProfessionalPlan.rotationWeek(on: d("2026-11-10"), anchor: anchor, weeks: 2, calendar: cal), 2)
        XCTAssertEqual(ProfessionalPlan.rotationWeek(on: d("2027-03-01"), anchor: anchor, weeks: 1, calendar: cal), 1)

        // I pasti seguono la settimana della rotazione, senza ricompilare il piano.
        func day(_ week: Int, _ weekday: Int?, _ grams: Double) -> PlannedDay {
            PlannedDay(week: week, weekday: weekday, meals: [PlannedMeal(type: .lunch, foods: [PlannedFood(name: "Pasta integrale", grams: grams)])])
        }
        var p = plan()
        p.rotationWeeks = 2
        p.rotationAnchor = anchor
        p.mealPlan = [day(1, nil, 80), day(2, nil, 60)]
        XCTAssertEqual(p.validate(), [])
        XCTAssertEqual(p.plannedMeal(.lunch, on: d("2026-11-23"), calendar: cal)?.foods.first?.grams, 60)
        XCTAssertEqual(p.plannedMeal(.lunch, on: d("2026-11-30"), calendar: cal)?.foods.first?.grams, 80)

        p.mealPlan = [day(1, 2, 80), day(1, 2, 60)]
        XCTAssertEqual(p.validate(), [.mealPlanInvalid])
        p.mealPlan = [day(3, 2, 80)]
        XCTAssertEqual(p.validate(), [.mealPlanInvalid])
        p.rotationWeeks = 5
        p.mealPlan = []
        XCTAssertEqual(p.validate(), [.mealPlanInvalid])
    }

    func testOldPlanDecodesAsSingleWeek() throws {
        let json = #"{"professional":"doctor","calorieTarget":1600,"startDate":0,"confirmedAt":0,"mealPlan":[{"weekday":2,"meals":[]}]}"#
        let p = try JSONDecoder().decode(ProfessionalPlan.self, from: Data(json.utf8))
        XCTAssertEqual(p.rotationWeeks, 1)
        XCTAssertEqual(p.mealPlan.first?.week, 1)
    }
}
