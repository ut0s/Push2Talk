import ApplicationServices
import XCTest
@testable import Push2TalkInput

final class FocusTargetTests: XCTestCase {
  private final class Context {
    var pid: pid_t? = 100
    var element: AXUIElement? = AXUIElementCreateApplication(1001)
    var metadata = FocusMetadata(isSecure: false, isEditable: true)
    var text: String? = "before"
    var textReads = 0

    var environment: FocusEnvironment {
      FocusEnvironment(
        ownPID: 42, frontmostPID: { self.pid }, focusedElement: { _ in self.element },
        metadata: { _ in self.metadata }, text: { _ in self.textReads += 1; return self.text })
    }
  }

  func testCustomEditorCanStartWithoutReadingTextOrSubmitting() throws {
    let context = Context()
    context.metadata.isEditable = false
    let target = try XCTUnwrap(FocusTarget.capture(environment: context.environment))
    XCTAssertTrue(target.isCurrent)
    XCTAssertFalse(target.canSubmitAutomatically)
    context.text = "changed"
    XCTAssertFalse(target.hasNewText)
    XCTAssertEqual(context.textReads, 0)
  }

  func testUnavailableAccessibilityCanStartButNeverSubmit() throws {
    let context = Context()
    context.element = nil
    let target = try XCTUnwrap(FocusTarget.capture(environment: context.environment))
    XCTAssertTrue(target.isCurrent)
    XCTAssertFalse(target.canSubmitAutomatically)
    XCTAssertFalse(target.hasNewText)
    context.pid = 101
    XCTAssertFalse(target.isCurrent)
  }

  func testKnownTextFieldSubmitsOnlyNewTextInSameControl() throws {
    let context = Context()
    let target = try XCTUnwrap(FocusTarget.capture(environment: context.environment))
    XCTAssertTrue(target.canSubmitAutomatically)
    XCTAssertFalse(target.hasNewText)
    context.text = "after"
    XCTAssertTrue(target.hasNewText)
    context.element = AXUIElementCreateApplication(1002)
    XCTAssertFalse(target.isCurrent)
    XCTAssertFalse(target.hasNewText)
  }

  func testUnreadableTextDoesNotPreventStartingOrAuthorizeEnter() throws {
    let context = Context()
    context.text = nil
    let target = try XCTUnwrap(FocusTarget.capture(environment: context.environment))
    XCTAssertTrue(target.isCurrent)
    XCTAssertFalse(target.canSubmitAutomatically)
    context.text = "after"
    XCTAssertFalse(target.hasNewText)
  }

  func testSecureFieldCannotStartAndItsContentsAreNotRead() {
    let context = Context()
    context.metadata.isSecure = true
    XCTAssertNil(FocusTarget.capture(environment: context.environment))
    XCTAssertEqual(context.textReads, 0)
  }

  func testFallbackCancelsWhenFocusBecomesSecure() throws {
    let context = Context()
    context.element = nil
    let target = try XCTUnwrap(FocusTarget.capture(environment: context.environment))
    context.element = AXUIElementCreateApplication(1001)
    context.metadata.isSecure = true
    XCTAssertFalse(target.isCurrent)
  }

  func testOwnSettingsAndMissingApplicationCannotStart() {
    let context = Context()
    context.pid = 42
    XCTAssertNil(FocusTarget.capture(environment: context.environment))
    context.pid = nil
    XCTAssertNil(FocusTarget.capture(environment: context.environment))
  }
}
