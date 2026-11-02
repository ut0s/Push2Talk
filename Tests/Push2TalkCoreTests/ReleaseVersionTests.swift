import XCTest
@testable import Push2TalkCore

final class ReleaseVersionTests: XCTestCase {
  func testNumericOrderingAndReleaseTags() {
    XCTAssertEqual(ReleaseVersion("v1.2.3"), ReleaseVersion("1.2.3"))
    XCTAssertLessThan(ReleaseVersion("0.9.9")!, ReleaseVersion("1.0.0")!)
    XCTAssertLessThan(ReleaseVersion("1.9.0")!, ReleaseVersion("1.10.0")!)
    XCTAssertLessThan(ReleaseVersion("1.0.9")!, ReleaseVersion("1.0.10")!)
    XCTAssertFalse(ReleaseVersion("2.0.0")! < ReleaseVersion("1.0.0")!)
  }

  func testRejectsUnsupportedOrMalformedVersions() {
    for text in ["", "1", "1.2", "1.2.3.4", "1..3", "-1.2.3", "1.2.3-beta", "1.2.3+1", " 1.2.3", "v", "１.2.3", "999999999999999999999999.0.0"] {
      XCTAssertNil(ReleaseVersion(text), text)
    }
  }
}
