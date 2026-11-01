import AppKit
import Push2TalkCore

let instanceLock = SingleInstanceLock()
do {
  let directory = try FileManager.default.url(
    for: .applicationSupportDirectory, in: .userDomainMask,
    appropriateFor: nil, create: true
  ).appendingPathComponent("Push2Talk", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  guard try instanceLock.acquire(at: directory.appendingPathComponent("instance.lock")) else {
    exit(EXIT_SUCCESS)
  }
} catch {
  NSLog("Push2Talk could not acquire its instance lock: %@", error.localizedDescription)
  exit(EXIT_FAILURE)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
