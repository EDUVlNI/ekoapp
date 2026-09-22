import Foundation
final class LatestLevelWriter {
    private let queue = DispatchQueue(label: "lume.brightness", qos: .userInteractive)
    private var pending: (Double, (Double) -> Bool, (Bool) -> Void)?
    private(set) var isBusy = false
    private var generation: UInt64 = 0
    func cancelPending() { pending = nil; generation &+= 1 }
    func submit(_ level: Double, write: @escaping (Double) -> Bool, completion: @escaping (Bool) -> Void) {
        guard level.isFinite else { return }
        pending = (min(1, max(0, level)), write, completion)
        drain()
    }
    private func drain() {
        guard !isBusy, let request = pending else { return }
        pending = nil
        isBusy = true
        let token = generation
        queue.async {
            let success = request.1(request.0)
            DispatchQueue.main.async {
                self.isBusy = false
                if token == self.generation { request.2(success) }
                self.drain()
            }
        }
    }
}
let writer = LatestLevelWriter()
let lock = NSLock()
var values: [Double] = []
let start = Date()
for i in 0...200 {
    writer.submit(Double(i) / 200, write: { value in
        precondition(!Thread.isMainThread)
        Thread.sleep(forTimeInterval: 0.06)
        lock.lock(); values.append(value); lock.unlock()
        return true
    }, completion: { success in precondition(Thread.isMainThread && success) })
}
precondition(Date().timeIntervalSince(start) < 0.1)
RunLoop.main.run(until: Date().addingTimeInterval(0.6))
lock.lock(); let recorded = values; lock.unlock()
precondition(recorded == [0, 1])
precondition(!writer.isBusy)
print("PASS: 201 brightness requests coalesced into first/final hardware writes, UI unblocked, main-thread completion")

let cancelled = LatestLevelWriter()
var completed = false
cancelled.submit(0.5, write: { _ in Thread.sleep(forTimeInterval: 0.05); return true }, completion: { _ in completed = true })
cancelled.submit(0.9, write: { _ in fatalError("Cancelled queued write must not run") }, completion: { _ in completed = true })
cancelled.cancelPending()
RunLoop.main.run(until: Date().addingTimeInterval(0.15))
precondition(!completed && !cancelled.isBusy)
print("PASS cancelling pending brightness writes and stale completions")
