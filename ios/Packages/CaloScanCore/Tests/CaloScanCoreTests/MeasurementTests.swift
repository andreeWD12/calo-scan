import XCTest
@testable import CaloScanCore

final class MeasurementTests: XCTestCase {
    private func m(_ daysAgo: Int, waist: Double? = nil, arm: Double? = nil) -> BodyMeasurement {
        BodyMeasurement(date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!, waistCm: waist, armCm: arm)
    }

    func testChangesUseFirstAndLastValueOfEachMeasure() {
        let history = [m(0, waist: 80.5), m(30, waist: 84, arm: 30), m(10, arm: 31.2)]
        let changes = BodyMeasurement.changes(in: history)
        XCTAssertEqual(changes[.waist], -3.5)
        XCTAssertEqual(changes[.arm], 1.2)
        XCTAssertNil(changes[.hips])
    }

    func testInvalidKinds() {
        XCTAssertEqual(m(0, waist: 300).invalidKinds, [.waist])
        XCTAssertEqual(m(0, waist: 80, arm: 5).invalidKinds, [.arm])
        XCTAssertTrue(m(0, waist: 80).invalidKinds.isEmpty)
    }
}
