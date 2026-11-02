import Foundation

public struct ReleaseVersion: Comparable, Equatable {
  private let components: [Int]

  public init?(_ text: String) {
    let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var numbers: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(part) else { return nil }
      numbers.append(number)
    }
    components = numbers
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.components.lexicographicallyPrecedes(rhs.components)
  }
}
