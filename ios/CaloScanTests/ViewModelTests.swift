import XCTest
import CaloScanCore
@testable import CaloScan

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testPasswordRules() {
        XCTAssertFalse(AuthViewModel.passwordIssues("abc").isEmpty)
        XCTAssertTrue(AuthViewModel.passwordIssues("Calorie2026").isEmpty)
    }

    func testEmailValidation() {
        XCTAssertTrue(AuthViewModel.isValidEmail("nome@esempio.it"))
        XCTAssertFalse(AuthViewModel.isValidEmail("nome@"))
    }

    func testSignUpRequiresConsents() {
        let model = AuthViewModel(auth: NotConnectedService())
        model.email = "nome@esempio.it"
        model.password = "Calorie2026"
        model.passwordConfirmation = "Calorie2026"
        XCTAssertFalse(model.canSignUp)
        model.acceptedTerms = true
        model.confirmedMinimumAge = true
        XCTAssertTrue(model.canSignUp)
    }
}

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testHealthConsentRequiredToContinue() {
        let model = OnboardingViewModel(services: .preview(startOnboarding: true))
        model.next()                       // intro → consent
        XCTAssertEqual(model.step, .consent)
        XCTAssertFalse(model.canContinue)
        model.healthConsent = true
        XCTAssertTrue(model.canContinue)
    }

    func testUnderweightTargetRejected() {
        let model = OnboardingViewModel(services: .preview(startOnboarding: true))
        model.heightCm = 170
        model.targetWeightKg = 45          // BMI ≈ 15,6
        XCTAssertNotNil(model.targetWeightError)
        model.targetWeightKg = 60
        XCTAssertNil(model.targetWeightError)
    }

    func testCustomCaloriesBelowFloorRejected() {
        let model = OnboardingViewModel(services: .preview(startOnboarding: true))
        model.sex = .female; model.heightCm = 165; model.weightKg = 60
        model.activity = .sedentary; model.goal = .loseWeight
        model.customCalories = 900
        XCTAssertNotNil(model.customCaloriesError)
    }
}

final class DeepLinkTests: XCTestCase {
    func testURLParsing() {
        XCTAssertEqual(DeepLink(url: URL(string: "caloscan://scanner")!), .scanner)
        XCTAssertEqual(DeepLink(url: URL(string: "caloscan://log-weight")!), .logWeight)
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/scanner")!))
    }
}
