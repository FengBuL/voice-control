import Foundation

struct Monitor: Identifiable, Equatable {
    let id: String
    let name: String
}

struct VolumeReading: Equatable {
    let current: Int
    let maximum: Int
    var percent: Double { Double(current) / Double(maximum) * 100 }

    static func parse(_ output: String) -> VolumeReading? {
        let values = output.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }
        guard values.count == 2, values[1] > 0, values[1] <= 65535,
              values[0] >= 0, values[0] <= values[1] else { return nil }
        return VolumeReading(current: values[0], maximum: values[1])
    }

    static func rawValue(percent: Double, maximum: Int) -> Int {
        Int((min(100, max(0, percent)) * Double(maximum) / 100).rounded())
    }
}

enum MonitorParser {
    static func parse(_ output: String) -> [Monitor] {
        let pattern = #"^\[\d+\] (.+) \(([0-9A-Fa-f-]{36})\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let text = String(line)
            guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let name = Range(match.range(at: 1), in: text),
                  let id = Range(match.range(at: 2), in: text), UUID(uuidString: String(text[id])) != nil else { return nil }
            return Monitor(id: String(text[id]), name: String(text[name]))
        }
    }
}

struct CommandResult {
    let code: Int32
    let output: String
}

enum DDCCommand {
    // Called only from the serial hardware queue. No shell or elevated helper.
    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 5) -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch {
            return CommandResult(code: -1, output: error.localizedDescription)
        }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { if process.isRunning { process.terminate() } }
        timer.resume()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()
        return CommandResult(code: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
