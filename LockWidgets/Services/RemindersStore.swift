import AppKit
import EventKit

/// Incomplete reminders from every list, soonest due first.
final class RemindersStore: ObservableObject {
    static let shared = RemindersStore()

    struct Item: Identifiable {
        let id: String
        let title: String
        let due: Date?
        let color: NSColor
        let isFlagged: Bool
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .reminder)

    private let store = EKEventStore()
    private var timer: Timer?

    var hasAccess: Bool { status == .fullAccess }

    private init() {
        #if DEBUG
        if WidgetGallery.isRendering { return } // Sample data only.
        #endif
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.reload()
        }
        reload()
    }

    func requestAccess() {
        guard status == .notDetermined else { return }
        store.requestFullAccessToReminders { [weak self] _, _ in
            DispatchQueue.main.async { self?.reload() }
        }
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
    }

    /// Adds a reminder to the default list, from Light's to-dos.
    func add(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasAccess, !title.isEmpty, let list = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        try? store.save(reminder, commit: true)
        reload()
    }

    /// Ticks a reminder off.
    func complete(_ id: String) {
        items.removeAll { $0.id == id }
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .reminder)
        guard hasAccess else {
            items = []
            return
        }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? [])
                .map { reminder in
                    Item(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "Untitled",
                        due: reminder.dueDateComponents?.date,
                        color: reminder.calendar.color,
                        isFlagged: reminder.priority == 1
                    )
                }
                .sorted { lhs, rhs in
                    switch (lhs.due, rhs.due) {
                    case let (left?, right?): left < right
                    case (_?, nil): true
                    default: false
                    }
                }
            DispatchQueue.main.async { self?.items = items }
        }
    }
}

#if DEBUG
extension RemindersStore {
    func loadSample() {
        let today = Calendar.current.startOfDay(for: .now)
        items = [
            Item(id: "1", title: "Book the train to Porto", due: today.addingTimeInterval(18 * 3600), color: .systemOrange, isFlagged: true),
            Item(id: "2", title: "Pick up the camera", due: today.addingTimeInterval(36 * 3600), color: .systemBlue, isFlagged: false),
            Item(id: "3", title: "Call Mum", due: nil, color: .systemGreen, isFlagged: false),
            Item(id: "4", title: "Renew the library books", due: today.addingTimeInterval(4 * 86400), color: .systemPurple, isFlagged: false),
        ]
        status = .fullAccess
    }
}
#endif
