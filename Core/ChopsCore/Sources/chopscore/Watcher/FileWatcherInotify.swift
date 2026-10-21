// FileWatcherInotify — Linux port of `Chops/Services/FileWatcher.swift` (plan T10).
//
// The macOS watcher opens each directory with `O_EVTONLY` and wraps the descriptor
// in a `DispatchSource.makeFileSystemObjectSource`. `O_EVTONLY` is Darwin-only, and
// GCD vnode file-system sources do not deliver directory change events on Linux, so
// the plan's pre-approved platform substitution applies: one inotify instance
// watches every directory and a `DispatchSourceRead` drains its queue.
//
// Behaviour kept from macOS:
//   * `watchDirectories` is a full reconfiguration (stop everything, then watch the
//     supplied existing directories; missing directories are logged and skipped).
//   * `stopAll` tears the watcher down and `deinit` calls it.
//   * everything is logged through `AppLogger.fileIO`.
//
// Deliberate Linux differences, all observable:
//   * the callback receives a `FileWatchEvent` with the concrete change kind and the
//     absolute path, instead of a debounced "path changed" signal. `chopsd` (T11)
//     owns rescan coalescing, and tests can assert create/modify/delete/rename.
//   * events are delivered asynchronously on `callbackQueue` (a private serial queue
//     by default) so a consumer may reconfigure or stop the watcher from inside its
//     callback without deadlocking the inotify reader.
//   * transient file descriptors are tolerated: `inotify_add_watch` failures for a
//     single directory (for example ENOSPC on the watch limit or ENOENT when the
//     directory disappears mid-setup) are logged and skipped, `read` retries EINTR,
//     and stale event handlers from a previous generation discard their events.

#if canImport(Glibc)
import Dispatch
import Foundation
import Glibc

/// One raw inotify change, translated into a stable public shape.
///
/// Renames arrive as two events sharing the same non-zero `cookie`: `renamedFrom`
/// for the old name and `renamedTo` for the new one. Create/modify/delete events
/// carry cookie `0`. `path` is always absolute and rooted at the watched directory.
public struct FileWatchEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case created
        case modified
        case deleted
        case renamedFrom
        case renamedTo
    }

    public let kind: Kind
    public let path: String
    public let cookie: UInt32
    public let isDirectory: Bool

    public init(kind: Kind, path: String, cookie: UInt32 = 0, isDirectory: Bool = false) {
        self.kind = kind
        self.path = path
        self.cookie = cookie
        self.isDirectory = isDirectory
    }
}

/// inotify-backed directory watcher for Linux.
public final class FileWatcherInotify: @unchecked Sendable {
    public typealias EventHandler = @Sendable (FileWatchEvent) -> Void

    private struct Watch {
        let path: String
    }

    /// inotify mask. `IN_CLOSE_WRITE` is intentionally absent: `IN_MODIFY` already
    /// reports content writes, and close-write would duplicate every modification.
    private static let watchMask: UInt32 = UInt32(
        IN_CREATE
            | IN_MODIFY
            | IN_ATTRIB
            | IN_DELETE
            | IN_MOVED_FROM
            | IN_MOVED_TO
            | IN_DELETE_SELF
            | IN_MOVE_SELF
    )

    private let callback: EventHandler
    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let bufferSize = 64 * 1024
    private let lock = NSLock()

    private var inotifyFileDescriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var watches: [Int32: Watch] = [:]
    /// Incremented on every stop so in-flight event handlers from an old descriptor
    /// cannot report into a newly configured watcher (fd numbers get reused).
    private var generation: UInt64 = 0

    /// - Parameters:
    ///   - callback: receives every change, asynchronously.
    ///   - queue: serial queue that owns the inotify descriptor and its reader.
    ///   - callbackQueue: queue that executes `callback`; injectable for tests.
    public init(
        callback: @escaping EventHandler,
        queue: DispatchQueue = DispatchQueue(
            label: "md.chops.filewatcher.inotify",
            qos: .utility
        ),
        callbackQueue: DispatchQueue = DispatchQueue(
            label: "md.chops.filewatcher.callback",
            qos: .utility
        )
    ) {
        self.callback = callback
        self.queue = queue
        self.callbackQueue = callbackQueue
    }

    /// Convenience used by tests and chopsd: inject the watched directories up front.
    public convenience init(directories: [String], callback: @escaping EventHandler) {
        self.init(callback: callback)
        watchDirectories(directories)
    }

    public var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inotifyFileDescriptor >= 0 && source != nil
    }

    /// Watched directory paths, sorted for stable diagnostics.
    public var watchedDirectories: [String] {
        lock.lock()
        defer { lock.unlock() }
        return watches.values.map(\.path).sorted()
    }

    /// Replaces the watched set. Missing/unwatchable directories are logged and
    /// skipped; the watcher still runs if at least one directory could be watched.
    public func watchDirectories(_ paths: [String]) {
        stopAll()

        let fd = inotify_init1(Int32(IN_NONBLOCK | IN_CLOEXEC))
        guard fd >= 0 else {
            AppLogger.fileIO.warning(
                "Failed to create inotify instance",
                metadata: ["errno": "\(errno)"]
            )
            return
        }

        var registered: [Int32: Watch] = [:]
        for rawPath in paths {
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                // Parity with macOS: the caller supplies candidate tool directories,
                // and tools that are not installed simply have no directory yet.
                AppLogger.fileIO.warning("Failed to watch: \(path)")
                continue
            }

            let descriptor = path.withCString { pointer in
                inotify_add_watch(fd, pointer, Self.watchMask)
            }
            guard descriptor >= 0 else {
                // Transient fd-style failures (ENOSPC watch limit, ENOMEM, ENOENT
                // when the directory vanished between the stat and the add) only
                // cost this one directory, never the whole watcher.
                AppLogger.fileIO.warning(
                    "Failed to watch: \(path)",
                    metadata: ["errno": "\(errno)"]
                )
                continue
            }

            if descriptor != 0, registered[descriptor] != nil {
                // A wd that was already in use for another path (only possible after
                // the kernel recycled one) is retargeted to the newest path.
                AppLogger.fileIO.debug("inotify reused watch descriptor \(descriptor)")
            }
            registered[descriptor] = Watch(path: path)
        }

        guard !registered.isEmpty else {
            close(fd)
            AppLogger.fileIO.warning("No directories could be watched")
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        lock.lock()
        generation &+= 1
        let currentGeneration = generation
        inotifyFileDescriptor = fd
        watches = registered
        self.source = source
        lock.unlock()

        source.setEventHandler { [weak self] in
            self?.drainEvents(generation: currentGeneration)
        }
        // The cancel handler owns closing the descriptor. Closing it here instead
        // would race a read that is already in flight; leaving it open until
        // cancellation also guarantees a replacement watcher cannot receive the
        // same fd number while the old source is still unwinding.
        source.setCancelHandler { close(fd) }
        source.resume()

        AppLogger.fileIO.notice(
            "Watching \(registered.count) directories",
            metadata: ["directories": "\(registered.values.map(\.path).sorted())"]
        )
    }

    /// Stops watching and closes the inotify descriptor. Safe to call repeatedly and
    /// from a callback (the reader is cancelled through Dispatch, never joined).
    public func stopAll() {
        lock.lock()
        let source = self.source
        let fd = inotifyFileDescriptor
        self.source = nil
        self.inotifyFileDescriptor = -1
        self.watches.removeAll()
        generation &+= 1
        lock.unlock()

        guard let source else {
            if fd >= 0 {
                close(fd)
            }
            return
        }
        source.cancel()
    }

    deinit {
        stopAll()
    }

    // MARK: - Reading

    private func drainEvents(generation expectedGeneration: UInt64) {
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            lock.lock()
            let isCurrent = generation == expectedGeneration && inotifyFileDescriptor >= 0
            let fd = inotifyFileDescriptor
            lock.unlock()
            guard isCurrent, fd >= 0 else { return }

            let count = read(fd, &buffer, buffer.count)
            AppLogger.fileIO.debug(
                "inotify read",
                metadata: ["bytes": "\(count)", "errno": "\(errno)"]
            )
            if count < 0 {
                switch errno {
                case EINTR:
                    continue
                case EAGAIN, EWOULDBLOCK:
                    return
                default:
                    // EBADF lands here when a callback stopped the watcher while this
                    // read was queued; that is a clean stop, not an error.
                    if errno == EBADF {
                        return
                    }
                    AppLogger.fileIO.error(
                        "inotify read failed",
                        metadata: ["errno": "\(errno)"]
                    )
                    return
                }
            }
            if count == 0 {
                return
            }

            let events = decode(buffer, byteCount: count)
            for event in events {
                deliver(event)
            }
        }
    }

    private func decode(_ buffer: [UInt8], byteCount: Int) -> [FileWatchEvent] {
        lock.lock()
        let snapshot = watches
        lock.unlock()

        var events: [FileWatchEvent] = []
        buffer.withUnsafeBytes { raw in
            var offset = 0
            let headerSize = MemoryLayout<inotify_event>.size

            while offset + headerSize <= byteCount {
                let event = raw.loadUnaligned(fromByteOffset: offset, as: inotify_event.self)
                let nameStart = offset + headerSize
                let nameLength = Int(event.len)
                guard nameStart + nameLength <= byteCount else { break }

                let nameBytes = raw[nameStart..<(nameStart + nameLength)]
                let name = String(decoding: nameBytes.prefix { $0 != 0 }, as: UTF8.self)
                offset = nameStart + nameLength

                let mask = event.mask
                if mask & UInt32(IN_IGNORED) != 0 {
                    // The kernel dropped this watch (directory deleted or unmounted).
                    lock.lock()
                    watches[event.wd] = nil
                    lock.unlock()
                    continue
                }
                if mask & UInt32(IN_Q_OVERFLOW) != 0 {
                    AppLogger.fileIO.error("inotify queue overflowed; events were lost")
                    continue
                }
                guard let watch = snapshot[event.wd] else { continue }

                let path = name.isEmpty
                    ? watch.path
                    : watch.path + "/" + name
                let isDirectory = mask & UInt32(IN_ISDIR) != 0

                if mask & UInt32(IN_MOVED_FROM) != 0 {
                    events.append(
                        FileWatchEvent(
                            kind: .renamedFrom,
                            path: path,
                            cookie: event.cookie,
                            isDirectory: isDirectory
                        )
                    )
                } else if mask & UInt32(IN_MOVED_TO) != 0 {
                    events.append(
                        FileWatchEvent(
                            kind: .renamedTo,
                            path: path,
                            cookie: event.cookie,
                            isDirectory: isDirectory
                        )
                    )
                } else if mask & UInt32(IN_CREATE) != 0 {
                    events.append(
                        FileWatchEvent(kind: .created, path: path, isDirectory: isDirectory)
                    )
                } else if mask & UInt32(IN_DELETE) != 0 {
                    events.append(
                        FileWatchEvent(kind: .deleted, path: path, isDirectory: isDirectory)
                    )
                } else if mask & (UInt32(IN_MODIFY) | UInt32(IN_ATTRIB)) != 0 {
                    events.append(
                        FileWatchEvent(kind: .modified, path: path, isDirectory: isDirectory)
                    )
                }
                // IN_DELETE_SELF / IN_MOVE_SELF only describe the watched root. They
                // are followed by IN_IGNORED (handled above), so no child event is
                // synthesised for them.
            }
        }
        return events
    }

    private func deliver(_ event: FileWatchEvent) {
        AppLogger.fileIO.debug(
            "File change detected: \(event.kind.rawValue)",
            metadata: ["path": "\(event.path)"]
        )
        let callback = self.callback
        callbackQueue.async {
            callback(event)
        }
    }
}
#endif
