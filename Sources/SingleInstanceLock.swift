import Foundation
import Darwin

// The kernel releases the lock when the process exits, including after a crash.
// Keep the file in place: unlinking it could let two processes lock different inodes.
final class SingleInstanceLock {
    private let descriptor: Int32
    let acquired: Bool

    init(url: URL) throws {
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            descriptor = fd
            acquired = true
        } else {
            let code = errno
            close(fd)
            guard code == EWOULDBLOCK else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
            descriptor = -1
            acquired = false
        }
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }
}
