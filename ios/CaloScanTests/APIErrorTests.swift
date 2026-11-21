import XCTest
@testable import CaloScan

final class APIErrorTests: XCTestCase {
    func testQuotaExceededParsed() {
        let body = #"{"error":{"code":"quota_exceeded","plan":"free"}}"#.data(using: .utf8)
        XCTAssertEqual(APIError.from(status: 429, body: body), .quotaExceeded(plan: "free"))
    }

    func testUnauthorizedFallback() {
        XCTAssertEqual(APIError.from(status: 401, body: nil), .unauthorized)
    }

    func testOnlyTransientErrorsRetry() {
        XCTAssertTrue(APIError.server(status: 503).isRetryable)
        XCTAssertFalse(APIError.server(status: 400).isRetryable)
        XCTAssertFalse(APIError.unauthorized.isRetryable)
    }
}
