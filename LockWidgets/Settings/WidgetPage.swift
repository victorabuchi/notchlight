import PhotosUI
import SwiftUI

struct WidgetPage: View {
    let kind: WidgetKind

    var body: some View {
        Form {
            Section {
                WidgetHeader(kind: kind)
            }

            switch kind {
            case .clock: ClockOptions()
            case .weather: WeatherOptions()
            case .calendar: CalendarOptions()
            case .nowPlaying: NowPlayingOptions()
            case .lyrics: LyricsOptions()
            case .battery: BatteryOptions()
            case .countdown: CountdownOptions()
            case .pomodoro: PomodoroOptions()
            case .stopwatch: StopwatchOptions()
            case .stickyNote: EmptyView()
            case .reminders: RemindersOptions()
            case .system: EmptyView()
            case .news: NewsOptions()
            case .stocks: StocksOptions()
            case .photos: PhotosOptions()
            case .earth: EarthOptions()
            case .dailyBrief: EmptyView()
            case .location: LocationOptions()
            case .musicCard: MusicCardOptions()
            case .favorites: FavoritesOptions()
            case .activity: ActivityOptions()
            }
        }
        .formStyle(.grouped)
        .id(kind)
    }
}

/// Preview of the chosen style and size, with a button to add it to the layout.
private struct WidgetHeader: View {
    let kind: WidgetKind

    @ObservedObject private var layout = LayoutStore.shared
    @State private var style = ""
    @State private var size = WidgetSize.small
    @State private var added = false
    /// For One App and Two Apps: the apps the widget will open, chosen before it is added.
    @State private var apps: [String] = []
    @AppStorage(SettingsKey.favoriteApps) private var stored = ""

    var body: some View {
        let current = kind.style(style)
        let placed = layout.instances.filter { $0.kind == kind }.count
        let appCount = kind == .favorites ? FavoriteApps.count(for: current.id) : nil
        HStack(alignment: .top, spacing: 22) {
            PreviewStage(height: 230) {
                FittedWidget(instance: preview(current), box: CGSize(width: 300, height: 200))
            }
            .frame(minWidth: 260, maxWidth: 360)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    WidgetIcon(kind: kind, size: 30)
                    Text(kind.title).font(.system(size: 22, weight: .bold))
                }
                Text(kind.summary).foregroundStyle(.secondary)
                if kind.styles.count > 1 {
                    Picker("Style", selection: $style) {
                        ForEach(kind.styles) { Text($0.name).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                HStack(spacing: 6) {
                    ForEach(current.sizes) { option in
                        SizeChip(size: option, isSelected: option == size) { size = option }
                    }
                    Text(size.title).foregroundStyle(.secondary).padding(.leading, 4)
                }
                if let appCount {
                    HStack(spacing: 8) {
                        FavoriteAppMenus(count: appCount, apps: $apps)
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        let id = layout.add(kind, style: current.id, size: size)
                        if appCount != nil {
                            layout.update(id) { $0.config["apps"] = apps.joined(separator: ",") }
                        }
                        withAnimation { added = true }
                    } label: {
                        Label("Add Widget", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    if added {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
                Text(placed == 0 ? "Not on your lock screen yet." : "\(placed) on your lock screen. Move them in Layout Studio.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .onAppear {
            style = kind.defaultStyle.id
            size = kind.defaultStyle.sizes[0]
        }
        .onChange(of: style) {
            let sizes = kind.style(style).sizes
            if !sizes.contains(size) { size = sizes[0] }
            added = false
            // Start from your first favourites; the menus change them.
            if kind == .favorites { apps = FavoriteApps.apps(of: kind.sample(style: style, size: size), stored: stored) }
        }
        .onChange(of: size) { added = false }
        .onChange(of: apps) { added = false }
    }

    /// The widget as it will be added, with the apps chosen for One App and Two Apps.
    private func preview(_ style: WidgetStyle) -> WidgetInstance {
        var instance = kind.sample(style: style.id, size: size)
        if kind == .favorites, FavoriteApps.count(for: style.id) != nil {
            instance.config["apps"] = apps.joined(separator: ",")
        }
        return instance
    }
}

/// A small proportional tile representing a widget size.
struct SizeChip: View {
    let size: WidgetSize
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let points = size.points
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color.white : Color.secondary)
                .frame(width: points.width / 22, height: points.height / 22)
                .frame(width: 40, height: 28)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(size.title)
    }
}

private struct ClockOptions: View {
    @AppStorage(SettingsKey.use24Hour) private var use24Hour = false
    @AppStorage(SettingsKey.showSeconds) private var showSeconds = false
    @AppStorage(SettingsKey.worldClockZones) private var zones = WorldClock.defaultZones

    var body: some View {
        Section("Clock") {
            Toggle("24-hour time", isOn: $use24Hour)
            Toggle("Show seconds", isOn: $showSeconds)
        }
        Section {
            TextField("Cities", text: $zones, prompt: Text(WorldClock.defaultZones), axis: .vertical)
                .lineLimit(1 ... 3)
        } header: {
            Text("World Clock")
        } footer: {
            Text("Time zone names separated by commas, such as Europe/Paris or America/Los_Angeles.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct WeatherOptions: View {
    @ObservedObject private var weather = WeatherStore.shared
    @AppStorage(SettingsKey.weatherCity) private var city = ""
    @AppStorage(SettingsKey.fahrenheit) private var fahrenheit = SettingsKey.defaultFahrenheit
    @State private var draft = ""

    var body: some View {
        Section {
            LabeledContent("City") {
                HStack {
                    TextField("City", text: $draft, prompt: Text("Current location"))
                        .labelsHidden()
                        .onSubmit(apply)
                    Button("Apply", action: apply)
                        .disabled(draft == city)
                }
            }
            Picker("Units", selection: $fahrenheit) {
                Text("Celsius (°C)").tag(false)
                Text("Fahrenheit (°F)").tag(true)
            }
            .onChange(of: fahrenheit) { weather.refresh() }
            if let problem = weather.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("Leave the city empty to use your Mac's location. Forecasts from Open-Meteo, updated every 15 minutes.")
                .foregroundStyle(.secondary)
        }
        .onAppear { draft = city }
    }

    private func apply() {
        city = draft.trimmingCharacters(in: .whitespaces)
        weather.refresh()
    }
}

private struct CalendarOptions: View {
    @ObservedObject private var calendar = CalendarStore.shared
    @AppStorage(SettingsKey.calendarIncludeTomorrow) private var includeTomorrow = true

    var body: some View {
        Section("Events") {
            Toggle(isOn: $includeTomorrow) {
                Text("Include tomorrow")
                Text("Turn off to show only what is left today.")
            }
        }
        Section("Access") {
            LabeledContent("Calendar") {
                switch calendar.status {
                case .fullAccess:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .notDetermined:
                    Button("Allow Access") { calendar.requestAccess() }
                default:
                    Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                }
            }
        }
        .onAppear { calendar.reload() }
    }
}

private struct NowPlayingOptions: View {
    @ObservedObject private var music = NowPlayingStore.shared
    @AppStorage(SettingsKey.hideMusicWhenIdle) private var hideWhenIdle = true

    var body: some View {
        Section {
            Toggle(isOn: $hideWhenIdle) {
                Text("Hide when nothing is playing")
                Text("Shared with Live Lyrics.")
            }
            if music.needsPermission {
                LabeledContent("Automation access is off") {
                    Button("Open Privacy Settings") { music.openAutomationSettings() }
                }
            }
        } header: {
            Text("Now Playing")
        } footer: {
            Text("Works with Apple Music and Spotify. Notchlight only reads from a player that is already open and never launches one.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LyricsOptions: View {
    @ObservedObject private var lyrics = LyricsStore.shared
    @AppStorage(SettingsKey.hideMusicWhenIdle) private var hideWhenIdle = true

    var body: some View {
        Section {
            LabeledContent("Now") {
                switch lyrics.state {
                case .found: Text("\(lyrics.lines.count) lines for this song").foregroundStyle(.secondary)
                case .loading: Text("Getting lyrics…").foregroundStyle(.secondary)
                case .unavailable: Text("No lyrics for this song").foregroundStyle(.secondary)
                case .otherPlayer: Text("Play something in Apple Music").foregroundStyle(.secondary)
                case .idle: Text("Nothing playing").foregroundStyle(.secondary)
                }
            }
            Toggle("Hide when nothing is playing", isOn: $hideWhenIdle)
        } header: {
            Text("Apple Music Lyrics")
        } footer: {
            Text("These are Apple Music's own lyrics, timed line by line exactly as in Music. Notchlight reads them from Music on this Mac; nothing comes from anywhere else.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CountdownOptions: View {
    var body: some View {
        Section {
            Text("Each countdown has its own title and date. Select one in Layout Studio to set them.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PomodoroOptions: View {
    @ObservedObject private var timers = TimerStore.shared
    @AppStorage(TimerStore.focusMinutesKey) private var focus = 25
    @AppStorage(TimerStore.breakMinutesKey) private var shortBreak = 5
    @AppStorage(TimerStore.longBreakMinutesKey) private var longBreak = 15

    var body: some View {
        Section("Timer") {
            LabeledContent(timers.phase.title) {
                HStack {
                    Button(timers.pomodoroRunning ? "Pause" : "Start") { timers.togglePomodoro() }
                        .buttonStyle(.borderedProminent)
                    Button("Skip") { timers.skipPhase() }
                    Button("Reset") { timers.resetPomodoro() }
                }
            }
        }
        Section {
            Stepper("Focus: \(focus) min", value: $focus, in: 5 ... 90, step: 5)
            Stepper("Short break: \(shortBreak) min", value: $shortBreak, in: 1 ... 30)
            Stepper("Long break: \(longBreak) min", value: $longBreak, in: 5 ... 60, step: 5)
        } header: {
            Text("Sessions")
        } footer: {
            Text("A long break follows every four focus sessions. You can also start and pause from the menu bar.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct StopwatchOptions: View {
    @ObservedObject private var timers = TimerStore.shared

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                LabeledContent(timers.stopwatchElapsed(at: context.date).clockText) {
                    HStack {
                        Button(timers.stopwatchRunning ? "Stop" : "Start") { timers.toggleStopwatch() }
                            .buttonStyle(.borderedProminent)
                        Button("Reset") { timers.resetStopwatch() }
                    }
                }
                .monospacedDigit()
            }
        } header: {
            Text("Stopwatch")
        } footer: {
            Text("You can also start and stop it from the menu bar.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct RemindersOptions: View {
    @ObservedObject private var reminders = RemindersStore.shared

    var body: some View {
        Section("Access") {
            LabeledContent("Reminders") {
                switch reminders.status {
                case .fullAccess:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .notDetermined:
                    Button("Allow Access") { reminders.requestAccess() }
                default:
                    Button("Open Privacy Settings") { reminders.openPrivacySettings() }
                }
            }
        }
        .onAppear { reminders.reload() }
    }
}

private struct NewsOptions: View {
    @ObservedObject private var news = NewsStore.shared
    @AppStorage(NewsStore.feedKey) private var feed = NewsStore.sources[0].url
    @State private var custom = ""

    var body: some View {
        Section {
            Picker("Source", selection: $feed) {
                ForEach(NewsStore.sources, id: \.url) { Text($0.name).tag($0.url) }
                if !NewsStore.sources.contains(where: { $0.url == feed }) {
                    Text("Custom feed").tag(feed)
                }
            }
            .onChange(of: feed) { news.refresh() }
            LabeledContent("Custom RSS feed") {
                HStack {
                    TextField("https://…", text: $custom)
                        .labelsHidden()
                        .onSubmit(useCustom)
                    Button("Use", action: useCustom)
                        .disabled(URL(string: custom)?.scheme?.hasPrefix("http") != true)
                }
            }
            if let problem = news.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("News")
        } footer: {
            Text("Headlines refresh every 30 minutes. Any RSS or Atom feed works.")
                .foregroundStyle(.secondary)
        }
    }

    private func useCustom() {
        feed = custom.trimmingCharacters(in: .whitespaces)
        custom = ""
    }
}

private struct StocksOptions: View {
    @ObservedObject private var stocks = StocksStore.shared
    @AppStorage(StocksStore.symbolsKey) private var symbols = StocksStore.defaultSymbols
    @State private var draft = ""

    var body: some View {
        Section {
            LabeledContent("Symbols") {
                HStack {
                    TextField("Symbols", text: $draft)
                        .labelsHidden()
                        .onSubmit(apply)
                    Button("Apply", action: apply)
                        .disabled(draft == symbols)
                }
            }
            ForEach(stocks.quotes) { quote in
                LabeledContent(quote.symbol) {
                    Text("\(quote.priceText)  \(quote.changeText)")
                        .foregroundStyle(quote.change >= 0 ? .green : .red)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Watchlist")
        } footer: {
            Text("Separate symbols with commas. Use BTC-USD for crypto and EURUSD=X for currency pairs. The first symbol leads the Spotlight style. Prices from Yahoo Finance, updated every 5 minutes.")
                .foregroundStyle(.secondary)
        }
        .onAppear { draft = symbols }
    }

    private func apply() {
        symbols = draft.uppercased().replacingOccurrences(of: " ", with: "")
        draft = symbols
        stocks.refresh()
    }
}

private struct PhotosOptions: View {
    @ObservedObject private var photos = PhotosStore.shared
    @AppStorage(PhotosStore.sourceKey) private var source = PhotosStore.Source.favorites
    @AppStorage(PhotosStore.intervalKey) private var interval = 15

    var body: some View {
        Section {
            Picker("Show", selection: $source) {
                ForEach(PhotosStore.Source.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: source) { photos.next() }
            if source == .chosen {
                ChosenPhotosEditor()
            } else if source == .folder {
                LabeledContent("Folder") {
                    HStack {
                        Text(photos.folderName ?? "None chosen")
                            .foregroundStyle(.secondary)
                        Button("Choose…") { photos.chooseFolder() }
                    }
                }
            } else if !photos.libraryAccess {
                LabeledContent("Photos access") {
                    Button("Allow Access") { photos.requestAccess() }
                }
            }
            Picker("Change photo", selection: $interval) {
                Text("Every minute").tag(1)
                Text("Every 5 minutes").tag(5)
                Text("Every 15 minutes").tag(15)
                Text("Every hour").tag(60)
            }
            .onChange(of: interval) { photos.restartTimer() }
            LabeledContent("Current photo") {
                Button("Show Another") { photos.next() }
            }
            if let problem = photos.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Photos")
        }
    }
}

/// Photos you choose for the Photos widget, from your library or from files, shown in the order you drag them
/// into. One photo stays put; several take turns.
private struct ChosenPhotosEditor: View {
    @ObservedObject private var photos = PhotosStore.shared
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        LabeledContent("Your photos") {
            HStack {
                PhotosPicker("Add from Photos…", selection: $picked, maxSelectionCount: 50, selectionBehavior: .ordered, matching: .images)
                Button("Add Files…") { photos.addFiles() }
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var images: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { images.append(data) }
                }
                photos.add(images)
                picked = []
            }
        }
        if photos.chosen.isEmpty {
            Text("Choose one photo to keep on your lock screen, or several to show one after another.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(photos.chosen.enumerated()), id: \.element.id) { index, photo in
                        Image(nsImage: photo.thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topLeading) {
                                Text("\(index + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.black.opacity(0.55), in: Capsule())
                                    .padding(4)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button { photos.remove(photo.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                                .help("Remove this photo")
                                .padding(4)
                            }
                            .draggable(photo.id)
                            .dropDestination(for: String.self) { ids, _ in
                                guard let id = ids.first, id != photo.id else { return false }
                                photos.move(id, before: photo.id)
                                return true
                            }
                    }
                    // Dropping past the last photo moves one to the end.
                    Color.clear
                        .frame(width: 44, height: 72)
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { ids, _ in
                            guard let id = ids.first else { return false }
                            photos.move(id, before: nil)
                            return true
                        }
                }
                .padding(.vertical, 4)
            }
            Text(photos.chosen.count == 1 ? "This photo stays on your lock screen." : "Shown one after another in this order. Drag a photo to move it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct EarthOptions: View {
    var body: some View {
        Section {
            Text("The globe is centred on your weather location and redrawn every 10 minutes, with night shading from the sun's real position.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct BatteryOptions: View {
    var body: some View {
        Section {
            Text("Shows charge, charging state and time remaining. Hidden automatically on Macs without a battery.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct LocationOptions: View {
    var body: some View {
        Section {
            Text("The map shows the same place as Weather: the city you set there, or your Mac's location if you haven't set one.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct MusicCardOptions: View {
    var body: some View {
        Section {
            Text("The card pops up when a song starts in Apple Music or Spotify and goes away when nothing is playing, like the player on the iPhone's lock screen.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ActivityOptions: View {
    @ObservedObject private var tracker = ActivityTracker.shared

    var body: some View {
        Section {
            LabeledContent("Today so far", value: tracker.total.durationText)
            Button("Start Today Over") { tracker.reset() }
        } footer: {
            Text("Notchlight adds up the time each app is in front, pausing while your Mac is locked or asleep. It keeps the count on this Mac and starts again each day.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct FavoritesOptions: View {
    @AppStorage(SettingsKey.favoriteApps) private var stored = ""
    @State private var target: String?

    var body: some View {
        let apps = FavoriteApps.list(stored)
        Section {
            ForEach(apps, id: \.self) { app in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .help("Drag to change the order")
                    Image(nsImage: AppInfo.icon(app))
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(AppInfo.name(app))
                    Spacer()
                    Button {
                        FavoriteApps.save(apps.filter { $0 != app })
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove \(AppInfo.name(app))")
                }
                .contentShape(Rectangle())
                .overlay(alignment: .top) {
                    // Where a dragged app will land.
                    if target == app { Capsule().fill(Color.accentColor).frame(height: 2).offset(y: -6) }
                }
                .draggable(app) {
                    Label { Text(AppInfo.name(app)) } icon: { Image(nsImage: FavoriteApps.menuIcon(app)) }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let moved = items.first, moved != app, apps.contains(moved) else { return false }
                    var list = apps.filter { $0 != moved }
                    list.insert(moved, at: list.firstIndex(of: app) ?? list.count)
                    FavoriteApps.save(list)
                    return true
                } isTargeted: { over in
                    target = over ? app : (target == app ? nil : target)
                }
            }
            Button("Add Apps…") { choose(after: apps) }
        } header: {
            Text("Apps")
        } footer: {
            Text("The Grid shows these in order: Small 4 apps, Medium 8, Wide 12 and Large 16. Drag an app to move it, or drop apps here from Finder to add them.")
                .foregroundStyle(.secondary)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let added = FavoriteApps.bundleIDs(of: urls).filter { !apps.contains($0) }
            guard !added.isEmpty else { return false }
            FavoriteApps.save(apps + added)
            return true
        }
    }

    private func choose(after apps: [String]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !apps.contains($0) }
        FavoriteApps.save(apps + added)
    }
}
