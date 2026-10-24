import SwiftUI

struct PlayerDetailView: View {
    @EnvironmentObject private var store: AppStore
    let selection: PlayerSelection
    @State private var details: PlayerDetails?
    @State private var loading = true
    @State private var error: String?
    @State private var section = 0
    @State private var attempt = 0

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    PlayerPhoto(url: selection.player.photoUrl, size: 150)
                    Text(selection.player.name).font(.title2.bold()).multilineTextAlignment(.center)
                    HStack {
                        Text(selection.player.team).foregroundStyle(.secondary)
                        RatingPill(value: selection.player.overall.value)
                    }
                    if let details {
                        Text([details.position, details.height > 0 ? "\(details.height) см" : ""]
                            .filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                    }
                    if selection.online {
                        Text("Текущие рейтинги сайта").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            if loading {
                ProgressView("Загружаем карточку…").frame(maxWidth: .infinity)
            } else if let error {
                Section {
                    Text(error).font(.subheadline)
                    Button("Попробовать ещё") { attempt += 1 }
                }
            } else if let details {
                Picker("Раздел", selection: $section) {
                    Text("Атрибуты").tag(0)
                    Text("Значки (\(details.badges.count))").tag(1)
                }.pickerStyle(.segmented).listRowBackground(Color.clear)
                if section == 0 {
                    ForEach(Array(details.attributes.enumerated()), id: \.offset) { _, group in
                        Section {
                            ForEach(Array(group.parameters.enumerated()), id: \.offset) { _, rating in
                                HStack {
                                    Text(rating.name ?? "Атрибут").font(.subheadline)
                                    Spacer()
                                    Text(rating.value == 0 ? "—" : "\(rating.value)")
                                        .monospacedDigit().foregroundStyle(statColor(rating.value))
                                }
                            }
                        } header: { Text("\(group.rating.name ?? "Атрибуты") · \(group.rating.value)") }
                    }
                } else if details.badges.isEmpty {
                    Text("У этого игрока нет значков.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(details.badges.enumerated()), id: \.offset) { _, badge in
                        HStack(alignment: .top, spacing: 12) {
                            PlayerPhoto(url: badge.photoUrl, size: 48)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(badge.name).font(.headline)
                                Text(badge.type).font(.caption).foregroundStyle(.orange)
                                Text(badge.description).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            if let url = URL(string: selection.player.url) {
                Section { Link("Открыть страницу игрока на 2KRatings", destination: url) }
            }
        }
        .navigationTitle("Карточка игрока").navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) {
            loading = true; error = nil
            defer { loading = false }
            do { details = try await store.playerDetails(for: selection.player, onlineSearch: selection.online) }
            catch is CancellationError { return }
            catch { self.error = error.localizedDescription }
        }
    }

    private func statColor(_ value: Int) -> Color {
        switch value {
        case 90...: return .green
        case 80..<90: return .mint
        case 70..<80: return .orange
        default: return .secondary
        }
    }
}

struct OnlineSearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Player] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: PlayerSelection?

    var body: some View {
        List {
            Section {
                Text("Поиск по всем игрокам на сайте 2KRatings. Здесь показываются текущие рейтинги сайта, независимо от выбранного ростера.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Ищем игроков…") }
            if let error { Text(error).foregroundStyle(.secondary) }
            ForEach(results) { player in
                Button { selected = PlayerSelection(player: player, online: true) } label: { PlayerRow(player: player) }
                    .buttonStyle(.plain)
            }
            if !loading && error == nil && results.isEmpty {
                Text(query.count < 2 ? "Введите минимум две буквы имени." : "Игроки не найдены.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Поиск в интернете").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Например, LeBron")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        .navigationDestination(item: $selected) { selection in PlayerDetailView(selection: selection) }
        .task(id: query) {
            results = []; error = nil; loading = false
            guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                loading = true
                let found = try await store.service.search(query)
                try Task.checkCancellation()
                results = found
                loading = false
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled else { return }
                loading = false; self.error = error.localizedDescription
            }
        }
    }
}
