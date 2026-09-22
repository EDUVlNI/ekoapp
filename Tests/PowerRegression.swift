import AppKit
import Combine
import IOKit.ps

@main
struct PowerRegression {
    @MainActor static func main() {
        precondition(StatusModel.bounded(.nan, range: 0.75...1.6, fallback: 1) == 1)
        precondition(StatusModel.bounded(5, range: 0.75...1.6, fallback: 1) == 1.6)
        precondition(StatusModel.bounded(-1, range: 0...1, fallback: 0.92) == 0)
        var reads = 0
        let model = StatusModel(powerReader: {
            precondition(Thread.isMainThread)
            reads += 1
            return .init(level: 0.42, hasBattery: true, charging: false, connected: false, lowPower: false)
        })
        let manual = model.showsPercentage
        let automatic = model.showsPercentageWhileCharging
        defer {
            model.showsPercentage = manual
            model.showsPercentageWhileCharging = automatic
            model.stop()
        }
        model.showsPercentage = false
        model.showsPercentageWhileCharging = true
        var events = 0
        let token = model.$powerState.dropFirst().sink { state in
            precondition(Thread.isMainThread)
            precondition(state.level.isFinite && (0...1).contains(state.level))
            events += 1
        }
        for _ in 0..<500 {
            model.applyPowerState(.init(level: 0.5, hasBattery: true, charging: true, connected: true, lowPower: false))
            precondition(model.effectiveShowsPercentage)
            model.applyPowerState(.init(level: 0.5, hasBattery: true, charging: false, connected: false, lowPower: true))
            precondition(!model.effectiveShowsPercentage)
        }
        precondition(events == 1000)
        model.applyPowerState(.init(level: 1, hasBattery: true, charging: false, connected: true, lowPower: false))
        precondition(model.effectiveShowsPercentage)
        let malformed = StatusModel.PowerState.from([kIOPSCurrentCapacityKey: Double.nan, kIOPSMaxCapacityKey: 0], lowPower: false)
        precondition(malformed.level == 0)
        model.installPowerObserver()
        model.installPowerObserver()
        let before = events
        DispatchQueue.global().async {
            for _ in 0..<100 {
                NotificationCenter.default.post(name: .NSProcessInfoPowerStateDidChange, object: ProcessInfo.processInfo)
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(2))
        precondition(events > before, "Background notifications must reach the main-thread publisher")
        precondition(reads == 100, "Deliver each notification exactly once without duplicate observers")
        withExtendedLifetime(token) {}
        print("PASS: 500 plug/unplug cycles, atomic state, automatic percentage, full battery, invalid readings, and 100 background power notifications published on main thread")
    }
}
