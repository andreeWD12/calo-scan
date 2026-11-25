import XCTest
@testable import CaloScanCore

/// Stessi casi di `supabase/functions/_shared/referral.test.ts` per la normalizzazione.
final class ReferralTests: XCTestCase {

    func testNormalize() {
        XCTAssertEqual(ReferralCode.normalize(" abcd-2345 "), "ABCD2345")
        XCTAssertEqual(ReferralCode.normalize("ABCD 2345"), "ABCD2345")
        XCTAssertNil(ReferralCode.normalize("ABCD-0345"))   // 0 escluso
        XCTAssertNil(ReferralCode.normalize("ABCD-I345"))   // I esclusa
        XCTAssertNil(ReferralCode.normalize("ABC2345"))
        XCTAssertNil(ReferralCode.normalize(""))
    }

    func testFormatted() {
        XCTAssertEqual(ReferralCode.formatted("ABCD2345"), "ABCD-2345")
    }

    func testRedeemURLOnlyWithOfferCode() {
        var s = ReferralStatus(code: "ABCD2345", shareURL: URL(string: "https://caloscan.app/i/ABCD2345")!, discountLabel: "30%")
        XCTAssertNil(s.redeemURL(appStoreID: "123"))
        s.reward = .available
        s.offerCode = "XYZ123"
        XCTAssertEqual(s.redeemURL(appStoreID: "123")?.absoluteString,
                       "https://apps.apple.com/redeem?ctx=offercodes&id=123&code=XYZ123")
    }
}
