import Foundation
import Darwin

@main enum SingleInstanceTests {
    static func child(_ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = arguments
        try process.run()
        return process
    }

    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count >= 3 {
            let instance = try SingleInstanceLock(url: URL(fileURLWithPath: arguments[2]))
            guard instance.acquired else { exit(2) }
            if arguments[1] == "--hold" {
                try Data().write(to: URL(fileURLWithPath: arguments[3]))
                withExtendedLifetime(instance) { _ = sleep(10) }
            }
            exit(0)
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceLockTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("instance.lock")

        do {
            let primary = try SingleInstanceLock(url: file)
            assert(primary.acquired)
            let duplicate = try child(["--probe", file.path])
            duplicate.waitUntilExit()
            assert(duplicate.terminationStatus == 2, "A competing process must be rejected")
            withExtendedLifetime(primary) {}
        }
        let afterNormalExit = try child(["--probe", file.path])
        afterNormalExit.waitUntilExit()
        assert(afterNormalExit.terminationStatus == 0, "Normal exit must release the lock")

        let ready = directory.appendingPathComponent("ready")
        let holder = try child(["--hold", file.path, ready.path])
        let deadline = Date().addingTimeInterval(3)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard FileManager.default.fileExists(atPath: ready.path) else {
            holder.terminate()
            holder.waitUntilExit()
            fatalError("Lock holder failed to start")
        }
        let whileHeld = try child(["--probe", file.path])
        whileHeld.waitUntilExit()
        assert(whileHeld.terminationStatus == 2)
        kill(holder.processIdentifier, SIGKILL)
        holder.waitUntilExit()
        let afterCrash = try SingleInstanceLock(url: file)
        assert(afterCrash.acquired, "A crash must not leave a stale lock")
        assert(FileManager.default.fileExists(atPath: file.path), "Lock file must stay in place")
        withExtendedLifetime(afterCrash) {}

        do {
            _ = try SingleInstanceLock(url: directory)
            fatalError("An inaccessible lock must fail closed")
        } catch {}
        print("Single instance checks passed: competing processes, normal exit, crash recovery and lock errors.")
    }
}
