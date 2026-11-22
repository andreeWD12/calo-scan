import XCTest
@testable import CaloScanCore

/// Stessi casi di `supabase/functions/_shared/eatingStyle.test.ts`.
final class EatingStyleTests: XCTestCase {

    private let none = EatingStyleScreening()

    func testAdultWithoutRisksSeesAllStyles() {
        let allowed = EatingStyleSafety.allowedStyles(ageYears: 30, bmi: 23, screening: none, hasProfessionalPlan: false)
        XCTAssertEqual(allowed, EatingStyle.allCases)
    }

    func testFastingBlockedForMinorsAndLowBMI() {
        XCTAssertEqual(EatingStyleSafety.blocks(for: .fasting16, ageYears: 17, bmi: 22, screening: none, hasProfessionalPlan: false), [.underAge])
        XCTAssertEqual(EatingStyleSafety.blocks(for: .fasting12, ageYears: 25, bmi: 18.2, screening: none, hasProfessionalPlan: false), [.lowBMI])
        XCTAssertEqual(EatingStyleSafety.blocks(for: .mediterranean, ageYears: 16, bmi: 17, screening: none, hasProfessionalPlan: false), [])
    }

    func testScreeningBlocksRestrictiveStylesOnly() {
        let ed = EatingStyleScreening(eatingDisorderHistory: true)
        let allowed = EatingStyleSafety.allowedStyles(ageYears: 30, bmi: 22, screening: ed, hasProfessionalPlan: false)
        XCTAssertEqual(allowed, [.balanced, .mediterranean, .highProtein, .vegetarian, .vegan])
        let pregnant = EatingStyleScreening(pregnantOrBreastfeeding: true, diabetesMedication: true)
        XCTAssertEqual(EatingStyleSafety.blocks(for: .moderateLowCarb, ageYears: 30, bmi: 22, screening: pregnant, hasProfessionalPlan: false),
                       [.pregnancy, .diabetesMedication])
    }

    func testProfessionalPlanTakesPriority() {
        XCTAssertTrue(EatingStyleSafety.allowedStyles(ageYears: 30, bmi: 22, screening: none, hasProfessionalPlan: true).isEmpty)
    }

    func testEatingWindow() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        let w = EatingWindow(startMinute: 12 * 60, hours: 8)   // 12:00–20:00
        let at = { (h: Int, m: Int) in cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: h, minute: m))! }
        XCTAssertFalse(w.isEating(at: at(11, 59), calendar: cal))
        XCTAssertTrue(w.isEating(at: at(12, 0), calendar: cal))
        XCTAssertTrue(w.isEating(at: at(19, 59), calendar: cal))
        XCTAssertFalse(w.isEating(at: at(20, 0), calendar: cal))
        XCTAssertEqual(w.nextChange(after: at(15, 0), calendar: cal), at(20, 0))
        XCTAssertEqual(w.nextChange(after: at(21, 0), calendar: cal), cal.date(byAdding: .day, value: 1, to: at(12, 0)))

        let night = EatingWindow(startMinute: 20 * 60, hours: 10)  // 20:00–06:00, a cavallo della mezzanotte
        XCTAssertTrue(night.isEating(at: at(23, 30), calendar: cal))
        XCTAssertTrue(night.isEating(at: at(5, 59), calendar: cal))
        XCTAssertFalse(night.isEating(at: at(6, 0), calendar: cal))
    }

    func testChoiceKeepsWindowLengthOfStyle() {
        let c = EatingStyleChoice(style: .fasting14, window: EatingWindow(startMinute: 9 * 60, hours: 3))
        XCTAssertEqual(c.window, EatingWindow(startMinute: 9 * 60, hours: 10))
        XCTAssertNil(EatingStyleChoice(style: .mediterranean, window: EatingWindow(startMinute: 0, hours: 8)).window)
        XCTAssertFalse(c.remindersEnabled)
    }
}
