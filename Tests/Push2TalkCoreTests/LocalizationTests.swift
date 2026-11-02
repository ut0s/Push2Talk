import XCTest
@testable import Push2TalkCore

final class LocalizationTests: XCTestCase {
  func testSystemLanguageUsesFirstSupportedPreference() {
    XCTAssertEqual(L10n.resolvedLanguage(.system, preferredLanguages: ["ja-JP", "en-US"]), .japanese)
    XCTAssertEqual(L10n.resolvedLanguage(.system, preferredLanguages: ["en-GB", "ja"]), .english)
    XCTAssertEqual(L10n.resolvedLanguage(.system, preferredLanguages: ["fr-FR", "ja_JP"]), .japanese)
    XCTAssertEqual(L10n.resolvedLanguage(.system, preferredLanguages: ["fr-FR"]), .english)
    XCTAssertEqual(L10n.resolvedLanguage(.system, preferredLanguages: []), .english)
  }

  func testExplicitLanguageOverridesSystem() {
    XCTAssertEqual(L10n.text("音声入力", language: .english, preferredLanguages: ["ja"]), "Dictation")
    XCTAssertEqual(L10n.text("音声入力", language: .japanese, preferredLanguages: ["en"]), "音声入力")
    XCTAssertEqual(L10n.text("REC", language: .english), "REC")
  }

  func testTranslationsPreserveFormatArgumentsAndLineBreaks() {
    for (key, value) in L10n.english {
      XCTAssertFalse(value.isEmpty, key)
      XCTAssertNil(value.range(of: "[ぁ-龯]", options: .regularExpression), key)
      XCTAssertEqual(key.components(separatedBy: "%@").count,
                     value.components(separatedBy: "%@").count, key)
      XCTAssertEqual(key.components(separatedBy: "\n").count,
                     value.components(separatedBy: "\n").count, key)
    }
    let key = "直近の受信: %@ / flags=0x%@"
    XCTAssertEqual(String(format: L10n.text(key, language: .english), "Right Option", "40"),
                   "Last event: Right Option / flags=0x40")
    XCTAssertEqual(String(format: L10n.text("Enterの受信: %@回", language: .japanese), "3"),
                   "Enterの受信: 3回")
  }
}
