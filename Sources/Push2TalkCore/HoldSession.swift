import Foundation

/// Timing and cancellation rules, independent of macOS event injection.
public struct HoldSession {
  public enum Action: Equatable { case start, stop, enter }
  public enum Phase: Equatable {
    case idle
    case arming(Double)
    case recording(Double)
    case stopping(Double)
    case settling(Double)
  }
  public private(set) var phase: Phase = .idle
  public var holdDelay = 0.18
  public var startupGrace = 0.65
  public var settleDelay = 0.8
  public var maximumDuration = 60.0
  public var sendEnter = true

  public init() {}

  public mutating func press(at now: Double) {
    guard phase == .idle else { return }
    phase = .arming(now + holdDelay)
  }

  public mutating func release(at now: Double) {
    switch phase {
    case .arming: phase = .idle
    case .recording(let started): phase = .stopping(max(now, started + startupGrace))
    default: break
    }
  }

  public mutating func tick(at now: Double) -> [Action] {
    switch phase {
    case .arming(let deadline) where now >= deadline:
      phase = .recording(now)
      return [.start]
    case .recording(let started) where now - started >= maximumDuration:
      return cancel()
    case .stopping(let deadline) where now >= deadline:
      phase = .settling(now + settleDelay)
      return [.stop]
    case .settling(let deadline) where now >= deadline:
      phase = .idle
      return sendEnter ? [.enter] : []
    default: return []
    }
  }

  public mutating func cancel() -> [Action] {
    defer { phase = .idle }
    switch phase {
    case .recording, .stopping: return [.stop]
    default: return []
    }
  }
}
