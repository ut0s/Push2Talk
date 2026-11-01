import Darwin
import Foundation

public final class SingleInstanceLock {
  private var descriptor: Int32 = -1

  public init() {}

  public func acquire(at url: URL) throws -> Bool {
    if descriptor >= 0 { return true }
    let candidate = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard candidate >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    if flock(candidate, LOCK_EX | LOCK_NB) != 0 {
      let code = errno
      close(candidate)
      if code == EWOULDBLOCK { return false }
      throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    descriptor = candidate
    return true
  }

  deinit {
    // Keep the file in place: unlinking it would let two processes lock different inodes.
    if descriptor >= 0 { close(descriptor) }
  }
}
