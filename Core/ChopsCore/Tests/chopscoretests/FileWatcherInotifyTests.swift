#if canImport(Glibc)
import Foundation
import Glibc
import XCTest
@testable import chopscore

/// Plan T10 watcher QA. Every test watches a fresh tmp copy of
/// `linux/fixtures/home`; the real `$HOME` is never read or written.
final class FileWatcherInotifyTests: StoreTestCase {
    func testWatcherEmitsCreateModifyDeleteAndRenameEvents() throws {
        let home = try StoreTestSupport.copyFixtureHome(into: scratch)
        let claudeSkills = home.appendingPathComponent(".claude/skills", isDirectory: true)
        let codexSkills = home.appendingPathComponent(".codex/skills", isDirectory: true)

        let collector = WatchEventCollector()
        let watcher = FileWatcherInotify(callback: collector.record)
        defer { watcher.stopAll() }
        watcher.watchDirectories([claudeSkills.path, codexSkills.path])

        XCTAssertTrue(watcher.isRunning)
        XCTAssertEqual(watcher.watchedDirectories, [claudeSkills.path, codexSkills.path].sorted())

        // create
        let created = claudeSkills.appendingPathComponent("t10-new.md")
        try createFile(at: created.path)
        let createdEvent = try XCTUnwrap(
            collector.wait(for: .created, pathSuffix: "t10-new.md"),
            "watcher must report the created file"
        )
        XCTAssertEqual(createdEvent.path, created.path)

        // modify
        let handle = try FileHandle(forWritingTo: created)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("# t10 watcher\n".utf8))
        try handle.close()
        let modifiedEvent = try XCTUnwrap(
            collector.wait(for: .modified, pathSuffix: "t10-new.md"),
            "watcher must report the content write"
        )
        XCTAssertEqual(modifiedEvent.path, created.path)

        // rename (moved-from + moved-to share one cookie)
        let renamed = claudeSkills.appendingPathComponent("t10-renamed.md")
        XCTAssertEqual(Glibc.rename(created.path, renamed.path), 0)
        let fromEvent = try XCTUnwrap(
            collector.wait(for: .renamedFrom, pathSuffix: "t10-new.md"),
            "watcher must report the rename source"
        )
        let toEvent = try XCTUnwrap(
            collector.wait(for: .renamedTo, pathSuffix: "t10-renamed.md"),
            "watcher must report the rename destination"
        )
        XCTAssertEqual(fromEvent.path, created.path)
        XCTAssertEqual(toEvent.path, renamed.path)
        XCTAssertNotEqual(fromEvent.cookie, 0)
        XCTAssertEqual(fromEvent.cookie, toEvent.cookie)

        // delete
        XCTAssertEqual(Glibc.remove(renamed.path), 0)
        let deletedEvent = try XCTUnwrap(
            collector.wait(for: .deleted, pathSuffix: "t10-renamed.md"),
            "watcher must report the deletion"
        )
        XCTAssertEqual(deletedEvent.path, renamed.path)

        let events = collector.events
        XCTAssertTrue(events.allSatisfy { $0.path.hasPrefix(home.path + "/") })
        XCTAssertTrue(events.allSatisfy { !$0.isDirectory }, "all fixture changes are files")

        // qa/t10/watcher.txt transcript: one deterministic line per observed event.
        for (index, event) in events.enumerated() {
            let relative = String(event.path.dropFirst(home.path.count + 1))
            print(
                "[t10] \(index): \(event.kind.rawValue) path=\(relative)"
                    + " cookie=\(event.cookie) isDirectory=\(event.isDirectory)"
            )
        }
        print("[t10] watchedDirectories=\(watcher.watchedDirectories)")
        print("[t10] eventCount=\(events.count)")
    }

    func testStopAllStopsDeliveringEventsAndCanBeRepeated() throws {
        let home = try StoreTestSupport.copyFixtureHome(into: scratch)
        let skills = home.appendingPathComponent(".claude/skills", isDirectory: true)

        let collector = WatchEventCollector()
        let watcher = FileWatcherInotify(callback: collector.record)
        watcher.watchDirectories([skills.path])
        XCTAssertTrue(watcher.isRunning)

        watcher.stopAll()
        watcher.stopAll()
        XCTAssertFalse(watcher.isRunning)
        XCTAssertTrue(watcher.watchedDirectories.isEmpty)

        let afterStop = skills.appendingPathComponent("t10-after-stop.md")
        XCTAssertTrue(FileManager.default.createFile(atPath: afterStop.path, contents: Data()))
        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertNil(collector.first(kind: .created, pathSuffix: "t10-after-stop.md"))
    }

    func testWatchDirectoriesReconfigurationKeepsDeliveringEvents() throws {
        let home = try StoreTestSupport.copyFixtureHome(into: scratch)
        let claudeSkills = home.appendingPathComponent(".claude/skills", isDirectory: true)
        let codexSkills = home.appendingPathComponent(".codex/skills", isDirectory: true)

        let collector = WatchEventCollector()
        let watcher = FileWatcherInotify(callback: collector.record)
        defer { watcher.stopAll() }

        watcher.watchDirectories([claudeSkills.path])
        let first = claudeSkills.appendingPathComponent("t10-before-reconfigure.md")
        try createFile(at: first.path)
        XCTAssertNotNil(collector.wait(for: .created, pathSuffix: "t10-before-reconfigure.md"))

        // Reconfiguration stops the old inotify instance and starts a new one; the
        // replacement must still deliver events despite the old descriptor unwinding.
        watcher.watchDirectories([codexSkills.path])
        XCTAssertEqual(watcher.watchedDirectories, [codexSkills.path])

        let second = codexSkills.appendingPathComponent("t10-after-reconfigure.md")
        try createFile(at: second.path)
        XCTAssertNotNil(collector.wait(for: .created, pathSuffix: "t10-after-reconfigure.md"))
    }

    func testMissingDirectoryIsSkippedButWatcherStillRuns() throws {
        let home = try StoreTestSupport.copyFixtureHome(into: scratch)
        let skills = home.appendingPathComponent(".claude/skills", isDirectory: true)
        let missing = home.appendingPathComponent(".not-installed/skills", isDirectory: true)

        let collector = WatchEventCollector()
        let watcher = FileWatcherInotify(callback: collector.record)
        defer { watcher.stopAll() }
        watcher.watchDirectories([missing.path, skills.path])

        XCTAssertTrue(watcher.isRunning)
        XCTAssertEqual(watcher.watchedDirectories, [skills.path])

        let created = skills.appendingPathComponent("t10-tolerated.md")
        try createFile(at: created.path)
        XCTAssertNotNil(collector.wait(for: .created, pathSuffix: "t10-tolerated.md"))
    }

    /// `FileManager.createFile` writes a `.dat.nosync…` temp and renames it into place,
    /// which inotify correctly reports as renamedTo. Tests want a literal create, so
    /// they use the POSIX call the watcher is meant to observe.
    private func createFile(at path: String) throws {
        let descriptor = Glibc.open(path, O_CREAT | O_WRONLY | O_TRUNC, mode_t(0o644))
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        Glibc.close(descriptor)
    }
}

private final class WatchEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FileWatchEvent] = []

    func record(_ event: FileWatchEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    var events: [FileWatchEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func first(kind: FileWatchEvent.Kind, pathSuffix: String) -> FileWatchEvent? {
        lock.lock()
        defer { lock.unlock() }
        return storage.first { $0.kind == kind && $0.path.hasSuffix(pathSuffix) }
    }

    func wait(
        for kind: FileWatchEvent.Kind,
        pathSuffix: String,
        timeout: TimeInterval = 5
    ) -> FileWatchEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let event = first(kind: kind, pathSuffix: pathSuffix) {
                return event
            }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        return first(kind: kind, pathSuffix: pathSuffix)
    }
}
#endif
