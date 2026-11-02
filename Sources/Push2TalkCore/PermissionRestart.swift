/// Coalesces permission grants into one restart attempt per process.
public struct PermissionRestart {
  public struct Permissions {
    public let accessibility: Bool
    public let posting: Bool
    public let listening: Bool

    public init(accessibility: Bool, posting: Bool, listening: Bool) {
      self.accessibility = accessibility
      self.posting = posting
      self.listening = listening
    }

    var ready: Bool { accessibility && posting }
  }

  public enum Action { case none, notice, restart }
  private var previous: Permissions?
  private var pending = false
  private var noticeAt: Double?
  private var attempted = false

  public init() {}

  public mutating func update(_ permissions: Permissions, idle: Bool, at time: Double) -> Action {
    defer { previous = permissions }
    guard !attempted else { return .none }
    if let previous,
      (!previous.accessibility && permissions.accessibility)
        || (!previous.posting && permissions.posting)
        || (!previous.listening && permissions.listening) {
      pending = true
      noticeAt = nil
    }
    guard pending, permissions.ready, idle else {
      noticeAt = nil
      return .none
    }
    guard let noticeAt else {
      self.noticeAt = time
      return .notice
    }
    guard time - noticeAt >= 2 else { return .notice }
    attempted = true
    return .restart
  }
}
