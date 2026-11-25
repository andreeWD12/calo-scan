import XCTest
@testable import CaloScanCore

/// Stessi casi di `supabase/functions/_shared/pregnancy.test.ts`.
final class PregnancyTests: XCTestCase {

    func testFoodsToAvoid() {
        let avoid: [(String, PregnancyFoodFlag.Risk)] = [
            ("Prosciutto crudo di Parma", .toxoplasmosis), ("Vino rosso", .alcohol), ("Gin tonic", .alcohol),
            ("Sushi misto", .listeria), ("Salmone affumicato", .listeria), ("Tiramisù", .salmonella),
            ("Gorgonzola", .listeria), ("Pesce spada alla griglia", .mercury), ("Paté di fegato", .vitaminA),
            ("Pancetta cruda", .toxoplasmosis),
        ]
        for (name, risk) in avoid {
            XCTAssertEqual(PregnancyFoodSafety.check(name), PregnancyFoodFlag(level: .avoid, risk: risk), name)
        }
    }

    func testFoodsToLimit() {
        XCTAssertEqual(PregnancyFoodSafety.check("Tonno in scatola"), PregnancyFoodFlag(level: .limit, risk: .mercury))
        XCTAssertEqual(PregnancyFoodSafety.check("Caffè espresso"), PregnancyFoodFlag(level: .limit, risk: .caffeine))
        XCTAssertEqual(PregnancyFoodSafety.check("Coca Cola"), PregnancyFoodFlag(level: .limit, risk: .caffeine))
    }

    func testNoFalseAlarmsOnCommonFoods() {
        for name in ["Prosciutto cotto", "Birra analcolica", "Salmone al forno", "Mozzarella", "Uova strapazzate",
                     "Pizza ai 4 formaggi con gorgonzola al forno", "Caffè decaffeinato", "Salame cotto", "Mele",
                     "Pane di frumento", "Cioccolato fondente", "Lievito di birra", "Salame di cioccolato",
                     "Spaghetti alla carbonara con guanciale", "Coppa di gelato"] {
            XCTAssertNil(PregnancyFoodSafety.check(name), name)
        }
    }

    func testToxoplasmosisImmunity() {
        XCTAssertEqual(PregnancyFoodSafety.check("Bresaola", toxoplasmosisImmune: true), PregnancyFoodFlag(level: .limit, risk: .listeria))
        XCTAssertEqual(PregnancyFoodSafety.check("Bresaola"), PregnancyFoodFlag(level: .avoid, risk: .toxoplasmosis))
        XCTAssertEqual(PregnancyFoodSafety.check("Carne cruda", toxoplasmosisImmune: true), PregnancyFoodFlag(level: .avoid, risk: .toxoplasmosis))
    }

    func testWeeksAndTrimesters() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let d = { (y: Int, m: Int, day: Int) in cal.date(from: DateComponents(year: y, month: m, day: day, hour: 12))! }
        let today = d(2026, 11, 22)
        XCTAssertEqual(PregnancyInfo(dueDate: d(2027, 5, 1)).week(on: today, calendar: cal), 17)
        XCTAssertEqual(PregnancyInfo(dueDate: d(2026, 11, 22)).week(on: today, calendar: cal), 40)
        XCTAssertEqual(PregnancyInfo(dueDate: d(2027, 8, 29)).week(on: today, calendar: cal), 1)
        XCTAssertEqual(PregnancyInfo(dueDate: d(2027, 2, 14)).week(on: today, calendar: cal), 28)
        XCTAssertEqual(PregnancyInfo(dueDate: d(2027, 2, 14)).trimester(on: today, calendar: cal), 3)
        XCTAssertTrue(PregnancyInfo.isValidDueDate(d(2027, 5, 1), today: today, calendar: cal))
        XCTAssertTrue(PregnancyInfo.isValidDueDate(d(2026, 11, 8), today: today, calendar: cal))
        XCTAssertFalse(PregnancyInfo.isValidDueDate(d(2026, 11, 7), today: today, calendar: cal))
        XCTAssertFalse(PregnancyInfo.isValidDueDate(d(2027, 9, 20), today: today, calendar: cal))
        XCTAssertTrue(PregnancyInfo(dueDate: d(2026, 11, 10)).isActive(on: today, calendar: cal))
        XCTAssertFalse(PregnancyInfo(dueDate: d(2026, 11, 1)).isActive(on: today, calendar: cal))
    }

    func testDueDateFromWeeksAndWeekPlan() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let d = { (y: Int, m: Int, day: Int) in cal.date(from: DateComponents(year: y, month: m, day: day, hour: 12))! }
        let today = d(2026, 11, 22)
        let due17 = PregnancyInfo.dueDate(week: 17, today: today, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: due17), DateComponents(year: 2027, month: 5, day: 2))
        XCTAssertEqual(PregnancyInfo(dueDate: due17).week(on: today, calendar: cal), 17)
        let due17p6 = PregnancyInfo.dueDate(week: 17, days: 6, today: today, calendar: cal)
        XCTAssertEqual(PregnancyInfo(dueDate: due17p6).week(on: today, calendar: cal), 17)
        XCTAssertEqual(PregnancyInfo(dueDate: due17p6).week(on: d(2026, 11, 23), calendar: cal), 18)
        let due41 = PregnancyInfo.dueDate(week: 41, days: 6, today: today, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: due41), DateComponents(year: 2026, month: 11, day: 9))
        XCTAssertTrue(PregnancyInfo.isValidDueDate(due41, today: today, calendar: cal))
        XCTAssertEqual(PregnancyInfo.dueDate(week: 0, today: today, calendar: cal), PregnancyInfo.dueDate(week: 1, today: today, calendar: cal))

        XCTAssertEqual(PregnancyNutrition.weekPlan(week: 13),
                       PregnancyWeekPlan(week: 13, trimester: 1, phase: .early, extraKcal: 70, extraProteinG: 1, nextChangeWeek: 14, nextExtraKcal: 260))
        XCTAssertEqual(PregnancyNutrition.weekPlan(week: 14),
                       PregnancyWeekPlan(week: 14, trimester: 2, phase: .middle, extraKcal: 260, extraProteinG: 9, nextChangeWeek: 28, nextExtraKcal: 500))
        XCTAssertEqual(PregnancyNutrition.weekPlan(week: 30),
                       PregnancyWeekPlan(week: 30, trimester: 3, phase: .late, extraKcal: 500, extraProteinG: 28, nextChangeWeek: nil, nextExtraKcal: nil))
        XCTAssertEqual(PregnancyNutrition.weekPlan(week: 37).phase, .term)
    }

    func testTargetsNeverInDeficit() throws {
        let m = try BodyMetrics(ageYears: 30, sex: .female, heightCm: 165, weightKg: 60)
        XCTAssertEqual(PregnancyNutrition.targets(metrics: m, activity: .lightlyActive, diet: .omnivore, trimester: 1),
                       DailyTargets(bmr: 1320, tdee: 1815, calorieTarget: 1885, proteinG: 97, carbsG: 233, fatG: 63, isAdjustedForSafety: false))
        XCTAssertEqual(PregnancyNutrition.targets(metrics: m, activity: .lightlyActive, diet: .omnivore, trimester: 2),
                       DailyTargets(bmr: 1320, tdee: 1815, calorieTarget: 2075, proteinG: 105, carbsG: 258, fatG: 69, isAdjustedForSafety: false))
        XCTAssertEqual(PregnancyNutrition.targets(metrics: m, activity: .lightlyActive, diet: .omnivore, trimester: 3),
                       DailyTargets(bmr: 1320, tdee: 1815, calorieTarget: 2315, proteinG: 124, carbsG: 281, fatG: 77, isAdjustedForSafety: false))
    }
}
