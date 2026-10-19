import AppKit

/// Countdown timers started from Light. Each one chimes when it reaches zero and stays, marked done, until
/// it's cleared.
final class CountdownStore: ObservableObject {
    static let shared = CountdownStore()

    struct Countdown: Identifiable, Equatable {
        let id = UUID()
        let duration: TimeInterval
        /// When it reaches zero while running; nil while paused.
        var end: Date?
        /// The time left while paused.
        var left: TimeInterval
        var isDone = false

        var isRunning: Bool { end != nil && !isDone }

        func remaining(at date: Date) -> TimeInterval {
            if isDone { return 0 }
            if let end { return max(0, end.timeIntervalSince(date)) }
            return left
        }
    }

    @Published private(set) var timers: [Countdown] = []
    private var ticker: Timer?

    func add(_ seconds: TimeInterval) {
        timers.append(Countdown(duration: seconds, end: .now.addingTimeInterval(seconds), left: seconds))
        startTicker()
    }

    func toggle(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isDone else { return }
        if let end = timers[index].end {
            timers[index].left = max(0, end.timeIntervalSinceNow)
            timers[index].end = nil
        } else {
            timers[index].end = .now.addingTimeInterval(timers[index].left)
            startTicker()
        }
    }

    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let ticker = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func tick() {
        let now = Date.now
        for index in timers.indices where timers[index].isRunning && timers[index].remaining(at: now) <= 0 {
            timers[index].isDone = true
            NSSound(named: "Glass")?.play()
        }
        if !timers.contains(where: \.isRunning) {
            ticker?.invalidate()
            ticker = nil
        }
    }

    #if DEBUG
    /// A running timer and a paused one, for pictures of Light.
    func loadSample() {
        timers = [
            Countdown(duration: 25 * 60, end: .now.addingTimeInterval(18 * 60 + 42), left: 0),
            Countdown(duration: 5 * 60, end: nil, left: 3 * 60 + 10),
        ]
    }
    #endif
}
