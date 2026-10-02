import Foundation

@main enum DomainTests {
    static func main() {
        assert(VolumeReading.parse("0 0") == nil)
        assert(VolumeReading.parse("101 100") == nil)
        assert(VolumeReading.parse("-1 100") == nil)
        assert(VolumeReading.parse("Invalid response") == nil)
        assert(VolumeReading.parse("5 10")?.percent == 50)
        assert(VolumeReading.parse("0 100")?.percent == 0)
        assert(VolumeReading.rawValue(percent: 50, maximum: 255) == 128)
        assert(VolumeReading.rawValue(percent: 150, maximum: 100) == 100)
        let lines = "[1] Monitor (HDMI) (00000000-0000-4000-8000-000000000001)\n[2] Broken (oops)\n"
        assert(MonitorParser.parse(lines).count == 1)
        assert(MonitorParser.parse(lines)[0].name == "Monitor (HDMI)")
        let failure = DDCCommand.run(executable: URL(fileURLWithPath: "/missing/helper"), arguments: [])
        assert(failure.code != 0)
        let echo = DDCCommand.run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["20 100"])
        assert(echo.code == 0 && VolumeReading.parse(echo.output)?.percent == 20)
        let started = Date()
        let timeout = DDCCommand.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.2)
        assert(timeout.code != 0 && Date().timeIntervalSince(started) < 3)
        print("Domain checks passed: malformed readings, scaling, display identity, helper failure and timeout.")
    }
}
