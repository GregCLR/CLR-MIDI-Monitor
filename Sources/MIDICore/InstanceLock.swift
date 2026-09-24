import Foundation
import Darwin

/// A process-held lock. The kernel releases it even if the process crashes.
/// Keep the lock file in place: unlinking it would allow two different inodes to be locked.
public final class InstanceLock {
    private let descriptor: Int32

    public init?(path: String) throws {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(fd)
            if failure == EWOULDBLOCK { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
        }
        descriptor = fd
    }

    deinit { close(descriptor) }
}
