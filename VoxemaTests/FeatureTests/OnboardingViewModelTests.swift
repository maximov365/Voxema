import XCTest
@testable import Voxema

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    // MARK: Navigation

    func testInitialStepIsWelcome() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.step, .welcome)
    }

    func testAdvanceFromWelcomeGoesToNextStep() {
        let vm = OnboardingViewModel()
        vm.advance()
        // Should move past welcome; may skip permission steps if already granted
        XCTAssertNotEqual(vm.step, .welcome)
    }

    func testBackFromWelcomeIsNoOp() {
        let vm = OnboardingViewModel()
        vm.goBack()
        XCTAssertEqual(vm.step, .welcome)
    }

    func testAdvanceAllWayToReady() {
        let vm = OnboardingViewModel()
        // Simulate all advance() calls — depends on permission state
        for _ in 0..<OnboardingStep.allCases.count {
            if !vm.step.isLast { vm.advance() }
        }
        XCTAssertEqual(vm.step, .ready)
    }

    func testBackNavigationFromMiddleStep() {
        let vm = OnboardingViewModel()
        // Force to configure step
        vm.advance(); vm.advance(); vm.advance()
        let stepBefore = vm.step
        vm.goBack()
        XCTAssertLessThan(vm.step.rawValue, stepBefore.rawValue)
    }

    // MARK: Completion flag

    func testCompleteCallsOnComplete() {
        let vm = OnboardingViewModel()
        var called = false
        vm.onComplete = { called = true }
        vm.complete()
        XCTAssertTrue(called)
    }

    // MARK: Download step

    func testSkipDownloadAdvancesStep() {
        let vm = OnboardingViewModel()
        // Navigate to download step
        for _ in 0..<OnboardingStep.download.rawValue {
            if !vm.step.isLast { vm.advance() }
        }
        let before = vm.step
        vm.skipModelDownload()
        XCTAssertNotEqual(vm.step, before)
        XCTAssertTrue(vm.skipDownload)
    }

    // MARK: Models

    func testWhisperModelsPopulatedOnInit() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.availableWhisperModels.isEmpty)
    }

    func testDefaultWhisperModelIsSmall() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.selectedWhisperModel, "whisper-small")
    }

    // MARK: Step properties

    func testWelcomeIsFirst() {
        XCTAssertTrue(OnboardingStep.welcome.isFirst)
        XCTAssertFalse(OnboardingStep.ready.isFirst)
    }

    func testReadyIsLast() {
        XCTAssertTrue(OnboardingStep.ready.isLast)
        XCTAssertFalse(OnboardingStep.welcome.isLast)
    }

    func testAllStepsCovered() {
        XCTAssertEqual(OnboardingStep.allCases.count, 7)
    }
}
