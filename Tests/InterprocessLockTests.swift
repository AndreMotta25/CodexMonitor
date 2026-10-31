import XCTest
@testable import CodexMonitorCore

final class InterprocessLockTests: XCTestCase {
    private func temporaryLockURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("codex-lock-test-\(UUID().uuidString)")
    }

    func testSeparateInstancesSerializeAsyncOperations() async throws {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let state = Counter()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await InterprocessLock(url: url).withLock {
                        await state.enter()
                        try await Task.sleep(for: .milliseconds(30))
                        await state.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        let maximum = await state.maximum
        let count = await state.count
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(count, 4)
    }

    func testThrowingOperationReleasesLock() async throws {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        enum Expected: Error { case failure }
        do {
            try await InterprocessLock(url: url).withLock { throw Expected.failure }
            XCTFail("Expected failure")
        } catch Expected.failure {}
        let value = try await InterprocessLock(url: url, timeout: 0.2).withLock { 42 }
        XCTAssertEqual(value, 42)
    }

    func testAnotherProcessExcludesAccessAndExitReleasesLock() async throws {
        let url = temporaryLockURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-u", "-c", "import sys,fcntl; f=open(sys.argv[1],'a'); fcntl.flock(f,fcntl.LOCK_EX); print('locked',flush=True); sys.stdin.buffer.read(1)", url.path]
        let ready = Pipe()
        let control = Pipe()
        child.standardOutput = ready
        child.standardInput = control
        try child.run()
        defer {
            if child.isRunning { child.terminate(); child.waitUntilExit() }
        }
        let signal = ready.fileHandleForReading.availableData
        XCTAssertEqual(String(data: signal, encoding: .utf8), "locked\n")
        do {
            try await InterprocessLock(url: url, timeout: 0.15).withLock { XCTFail("Entered while another process held the lock") }
            XCTFail("Expected contention")
        } catch InterprocessLock.LockError.busy {}
        try control.fileHandleForWriting.write(contentsOf: Data([1]))
        child.waitUntilExit()
        let acquired = try await InterprocessLock(url: url, timeout: 1).withLock { true }
        XCTAssertTrue(acquired)
    }

    private actor Counter {
        var active = 0
        var maximum = 0
        var count = 0
        func enter() { active += 1; maximum = max(maximum, active); count += 1 }
        func leave() { active -= 1 }
    }
}
