import SwiftUI

@main
struct NBA2KRandomizerApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).tint(.orange)
        }
    }
}

struct PlayerSelection: Identifiable, Hashable {
    let id = UUID()
    let player: Player
    var online = false
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedPlayer: PlayerSelection?

    var body: some View {
        TabView {
            NavigationStack { RandomizerView(onPlayer: showPlayer) }
                .tabItem { Label("Рандом", systemImage: "shuffle") }
            NavigationStack { RosterView(onPlayer: showPlayer) }
                .tabItem { Label("Игроки", systemImage: "person.3.fill") }
            NavigationStack { HistoryView(onPlayer: showPlayer) }
                .tabItem { Label("История", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
        }
        .sheet(item: $selectedPlayer) { selection in
            NavigationStack {
                PlayerDetailView(selection: selection)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") { selectedPlayer = nil }
                    } }
            }
        }
        .alert("Не удалось выполнить действие", isPresented: Binding(
            get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Понятно") { store.error = nil }
            } message: { Text(store.error ?? "") }
    }

    private func showPlayer(_ player: Player) { selectedPlayer = PlayerSelection(player: player) }
}

struct RandomizerView: View {
    @EnvironmentObject private var store: AppStore
    let onPlayer: (Player) -> Void
    @State private var playersCount = 1
    @State private var twoTeams = false
    @State private var positions = Set<Position>()
    @State private var gameID: UUID?
    @State private var showGame = false
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.dataset.version.rawValue).font(.largeTitle.bold())
                        Text(store.dataset.era.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack {
                        Text("\(store.engine.pool.count)").font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("в колоде").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("Состав") {
                Stepper("Игроков в команде: \(playersCount)", value: $playersCount, in: 1...5)
                Toggle("Две команды", isOn: $twoTeams)
            }
            Section {
                HStack(spacing: 8) {
                    ForEach(Position.allCases) { position in
                        Button {
                            if positions.contains(position) { positions.remove(position) }
                            else { positions.insert(position) }
                        } label: {
                            Text(position.rawValue).font(.subheadline.bold())
                                .frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(positions.contains(position) ? Color.orange : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(positions.contains(position) ? Color.black : Color.primary)
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Позиция \(position.rawValue)")
                            .accessibilityAddTraits(positions.contains(position) ? .isSelected : [])
                    }
                }.padding(.vertical, 4)
            } header: { Text("Позиции") } footer: {
                Text(positions.isEmpty ? "Без выбранных позиций — любые игроки. Повторов в колоде нет."
                     : "Выберите \(playersCount) позиций: по одной на игрока в каждой команде.")
            }
            Section {
                Button {
                    gameID = store.draw(playersPerTeam: playersCount, teamsCount: twoTeams ? 2 : 1,
                                        positions: Position.allCases.filter { positions.contains($0) })
                    showGame = gameID != nil
                } label: {
                    Label("Собрать команды", systemImage: "shuffle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).disabled(store.players.isEmpty || store.isLoading)
            }.listRowBackground(Color.clear)
            Section {
                LabeledContent("Сыграно", value: "\(store.engine.games.count)")
                LabeledContent("Использовано игроков", value: "\(store.engine.usedCount) / \(store.engine.total)")
                Button("Начать новую колоду", role: .destructive) { confirmReset = true }
                    .disabled(store.players.isEmpty)
            } footer: { Text("Новая колода очищает историю для выбранного ростера. История сохраняется между запусками приложения.") }
        }
        .navigationTitle("NBA 2K Randomizer")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showGame) {
            if let gameID { GameView(gameID: gameID, onPlayer: onPlayer) }
        }
        .confirmationDialog("Начать новую колоду и очистить её историю?", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Новая колода", role: .destructive) { store.reset() }
        }
    }
}

struct GameView: View {
    @EnvironmentObject private var store: AppStore
    let gameID: UUID
    let onPlayer: (Player) -> Void
    private var game: DraftGame? { store.engine.games.first { $0.id == gameID } }

    var body: some View {
        Group {
            if let game {
                List {
                    ForEach(0..<game.teamsCount, id: \.self) { team in
                        Section(game.teamsCount == 1 ? "Состав" : "Команда \(team + 1)") {
                            ForEach(game.slots.filter { $0.team == team }) { slot in
                                HStack {
                                    Button { onPlayer(slot.player) } label: { PlayerRow(player: slot.player) }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("draft-player")
                                    if store.engine.games.last?.id == game.id {
                                        Button { store.replace(gameID: game.id, slotID: slot.id) } label: {
                                            Image(systemName: "arrow.triangle.2.circlepath").padding(8)
                                        }.buttonStyle(.bordered)
                                            .accessibilityLabel("Заменить \(slot.player.name)")
                                    }
                                }
                            }
                        }
                    }
                    if !game.replacements.isEmpty {
                        Section("Замены") {
                            ForEach(game.replacements) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(change.oldPlayer.name).foregroundStyle(.secondary).strikethrough()
                                    Label(change.newPlayer.name, systemImage: "arrow.turn.down.right")
                                }.font(.subheadline)
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Игра недоступна", systemImage: "basketball",
                                       description: Text("Выбран другой ростер или начата новая колода."))
            }
        }.navigationTitle("Состав команды").navigationBarTitleDisplayMode(.inline)
    }
}

struct RosterView: View {
    @EnvironmentObject private var store: AppStore
    let onPlayer: (Player) -> Void
    @State private var filter = RosterFilter()
    @State private var showFilter = false
    @State private var showOnline = false
    private var filtered: [Player] { filter.apply(to: store.players) }

    var body: some View {
        List {
            Section {
                ForEach(filtered) { player in
                    Button { onPlayer(player) } label: { PlayerRow(player: player) }.buttonStyle(.plain)
                }
            } header: { Text("\(store.dataset.version.rawValue) · \(store.dataset.era.title) · \(filtered.count) игроков") }
        }
        .overlay {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: filter.name)
            }
        }
        .navigationTitle("Игроки")
        .searchable(text: $filter.name, prompt: "Найти в выбранном ростере")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showOnline = true } label: { Image(systemName: "globe") }
                    .accessibilityLabel("Поиск на сайте рейтингов")
                Button { showFilter = true } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                    .accessibilityLabel("Фильтры и сортировка")
            }
        }
        .sheet(isPresented: $showFilter) {
            NavigationStack {
                Form {
                    Picker("Команда", selection: $filter.team) {
                        Text("Все команды").tag("")
                        ForEach(Array(Set(store.players.map(\.team))).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Позиция", selection: $filter.position) {
                        Text("Любая").tag(Optional<Position>.none)
                        ForEach(Position.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    Picker("Сортировка", selection: $filter.sort) {
                        ForEach(SortField.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("По возрастанию", isOn: $filter.ascending)
                    Button("Сбросить фильтры") { filter = RosterFilter() }
                }.navigationTitle("Фильтры")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { showFilter = false } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showOnline) { NavigationStack { OnlineSearchView() } }
        .onChange(of: store.dataset) { _, _ in filter = RosterFilter() }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    let onPlayer: (Player) -> Void

    var body: some View {
        List {
            ForEach(Array(store.engine.games.enumerated().reversed()), id: \.element.id) { index, game in
                NavigationLink {
                    GameView(gameID: game.id, onPlayer: onPlayer)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Игра \(index + 1)").font(.headline)
                            Spacer()
                            Text(game.date, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(game.slots.map { $0.player.name }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        Text("Команд: \(game.teamsCount) · Игроков: \(game.slots.count) · Замен: \(game.replacements.count)")
                            .font(.caption).foregroundStyle(.orange)
                    }.padding(.vertical, 4)
                }
            }
        }
        .overlay {
            if store.engine.games.isEmpty {
                ContentUnavailableView("Пока нет игр", systemImage: "clock",
                    description: Text("Соберите первую команду во вкладке «Рандом»."))
            }
        }.navigationTitle("История")
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var version = GameVersion.k26
    @State private var era = Era.current
    @State private var confirmRefresh = false

    var body: some View {
        Form {
            Section {
                Picker("Игра", selection: $version) {
                    ForEach(GameVersion.allCases) { Text($0.title).tag($0) }
                }
                Picker("Игроки", selection: $era) {
                    ForEach(Era.allCases) { Text($0.title).tag($0) }
                }
                Button("Открыть ростер") { Task { await store.select(Dataset(version: version, era: era)) } }
                    .disabled(store.isLoading)
                if store.isLoading { ProgressView("Загружаем игроков…") }
                Text(store.status).font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Ростер") } footer: {
                Text("2K25 и 2K26 содержат данные из Android-приложения и работают без интернета. 2K27 использует текущие рейтинги сайта, как в оригинале. Фотографии загружаются через интернет.")
            }
            if store.dataset.version.isLive {
                Section {
                    Button("Обновить текущий ростер с сайта") { confirmRefresh = true }
                        .disabled(store.isLoading)
                } footer: { Text("Обновление начнёт новую колоду и очистит историю этого ростера. Остальные версии сохранятся.") }
            }
            Section("Личная версия") {
                Label("Данные и история хранятся на устройстве", systemImage: "iphone")
                Label("Без регистрации в приложении", systemImage: "person.crop.circle")
                Link("Источник Android-приложения", destination: URL(string: "https://github.com/AsdWELL/NBA2K-Randomizer-Android")!)
                Link("Источник рейтингов: 2KRatings", destination: URL(string: "https://www.2kratings.com")!)
                Text("Версия 1.0 · Для личного использования").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Настройки")
        .onAppear { version = store.dataset.version; era = store.dataset.era }
        .confirmationDialog("Обновить ростер и начать новую колоду?", isPresented: $confirmRefresh,
                            titleVisibility: .visible) {
            Button("Обновить", role: .destructive) { Task { await store.refresh() } }
        }
    }
}

struct PlayerRow: View {
    let player: Player
    var body: some View {
        HStack(spacing: 12) {
            PlayerPhoto(url: player.photoUrl, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(player.name).font(.subheadline.bold()).foregroundStyle(.primary)
                Text([player.team, player.position, player.height > 0 ? "\(player.height) см" : ""]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if player.threePointRating.value > 0 {
                    Text("3PT \(player.threePointRating.value)   DNK \(player.dunkRating.value)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 2)
            RatingPill(value: player.overall.value)
        }.padding(.vertical, 3).contentShape(Rectangle())
    }
}

struct PlayerPhoto: View {
    let url: String
    var size: CGFloat = 56
    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image { image.resizable().scaledToFit() }
            else { Image(systemName: "person.fill").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.secondary) }
        }.frame(width: size, height: size)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
    }
}

struct RatingPill: View {
    let value: Int
    var body: some View {
        Text(value == 0 ? "—" : "\(value)").font(.headline.monospacedDigit())
            .foregroundStyle(value >= 90 ? Color.orange : Color.primary)
            .padding(9).background((value >= 90 ? Color.orange : Color.secondary).opacity(0.14),
                                   in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Рейтинг \(value)")
    }
}
