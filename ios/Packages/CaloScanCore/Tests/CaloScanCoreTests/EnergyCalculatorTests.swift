import XCTest
@testable import CaloScanCore

/// Stessi casi di `supabase/functions/_shared/nutrition.test.ts`.
final class EnergyCalculatorTests: XCTestCase {

    func testBMRMale() throws {
        let m = try BodyMetrics(ageYears: 30, sex: .male, heightCm: 180, weightKg: 80)
        XCTAssertEqual(EnergyCalculator.bmr(m), 1780, accuracy: 0.001)
    }

    func testBMRFemale() throws {
        let m = try BodyMetrics(ageYears: 30, sex: .female, heightCm: 165, weightKg: 60)
        XCTAssertEqual(EnergyCalculator.bmr(m), 1320.25, accuracy: 0.001)
    }

    func testMaleModerateLoseWeight() throws {
        let m = try BodyMetrics(ageYears: 30, sex: .male, heightCm: 180, weightKg: 80)
        let t = EnergyCalculator.targets(metrics: m, activity: .moderatelyActive, goal: .loseWeight)
        XCTAssertEqual(t.tdee, 2759)
        XCTAssertEqual(t.calorieTarget, 2345)
        XCTAssertEqual(t.proteinG, 144)
        XCTAssertEqual(t.fatG, 78)
        XCTAssertEqual(t.carbsG, 266)
        XCTAssertFalse(t.isAdjustedForSafety)
    }

    func testFloorApplied() throws {
        let m = try BodyMetrics(ageYears: 70, sex: .female, heightCm: 150, weightKg: 45)
        let t = EnergyCalculator.targets(metrics: m, activity: .sedentary, goal: .loseWeight)
        XCTAssertEqual(t.calorieTarget, 1200)
        XCTAssertTrue(t.isAdjustedForSafety)
    }

    func testMinorNeverGetsDeficit() throws {
        let m = try BodyMetrics(ageYears: 16, sex: .male, heightCm: 175, weightKg: 70)
        let t = EnergyCalculator.targets(metrics: m, activity: .moderatelyActive, goal: .loseWeight)
        XCTAssertEqual(t.calorieTarget, t.tdee)
        XCTAssertTrue(t.isAdjustedForSafety)
    }

    func testInvalidMetricsRejected() {
        XCTAssertThrowsError(try BodyMetrics(ageYears: 30, sex: .male, heightCm: 20, weightKg: 80))
    }

    func testNutrientScaling() {
        let pasta = Nutrients(kcal: 350, proteinG: 12, carbsG: 72, fatG: 1.5)
        XCTAssertEqual(pasta.scaled(per100gTo: 80).kcal, 280, accuracy: 0.001)
    }
}
