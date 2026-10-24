import Foundation
import Combine

enum SnapshotLoader {
    static func decode<T: Decodable>(_ type: T.Type, name: String, bundle: Bundle = .main) throws -> T {
        guard let url = bundle.url(forResource: name, withExtension: "json") else { throw DataError.missingSnapshot }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var dataset = Dataset()
    @Published private(set) var players: [Player] = []
    @Published private(set) var engine = RandomizerEngine(players: [])
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var status = ""

    let service = RatingsService()
    private var details: [Int: PlayerDetails] = [:]
    private var onlineDetails: [String: PlayerDetails] = [:]
    private let directory: URL
    private let defaults: UserDefaults

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.defaults = defaults
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            if let saved = defaults.data(forKey: "dataset"), let value = try? JSONDecoder().decode(Dataset.self, from: saved) {
                dataset = value
            }
            try loadSaved(dataset)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func file(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }

    private func read<T: Decodable>(_ type: T.Type, name: String) throws -> T {
        if FileManager.default.fileExists(atPath: file(name).path) {
            return try JSONDecoder().decode(type, from: Data(contentsOf: file(name)))
        }
        return try SnapshotLoader.decode(type, name: name)
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: file(name), options: .atomic)
    }

    private func loadSaved(_ selection: Dataset) throws {
        let roster = try read([Player].self, name: selection.rosterName)
        guard !roster.isEmpty, Set(roster.map(\.id)).count == roster.count else { throw DataError.invalidData }
        let savedDetails = (try? read([PlayerDetails].self, name: selection.detailsName)) ?? []
        dataset = selection
        players = roster
        details = Dictionary(savedDetails.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let restored = try? JSONDecoder().decode(RandomizerEngine.self, from: Data(contentsOf: file("session_" + selection.key)))
        engine = restored?.isValid(for: roster) == true ? restored! : RandomizerEngine(players: roster)
        status = "\(roster.count) игроков · \(selection.version.rawValue) · \(selection.era.title)"
        defaults.set(try JSONEncoder().encode(selection), forKey: "dataset")
    }

    func select(_ selection: Dataset) async {
        guard !isLoading else { return }
        do { try loadSaved(selection) }
        catch DataError.missingSnapshot where selection.version.isLive {
            await refresh(selection)
        } catch { self.error = error.localizedDescription }
    }

    func refresh(_ selection: Dataset? = nil) async {
        guard !isLoading else { return }
        let selection = selection ?? dataset
        guard selection.version.isLive else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let roster = try await service.roster(era: selection.era)
            try write(roster, name: selection.rosterName)
            // Details are fetched for the selected player and stored separately.
            try write([PlayerDetails](), name: selection.detailsName)
            let newSession = RandomizerEngine(players: roster)
            try write(newSession, name: "session_" + selection.key)
            try loadSaved(selection)
        } catch is CancellationError {
            return
        } catch { self.error = error.localizedDescription }
    }

    func draw(playersPerTeam: Int, teamsCount: Int, positions: [Position]) -> UUID? {
        do {
            let game = try engine.draw(playersPerTeam: playersPerTeam, teamsCount: teamsCount, positions: positions)
            try saveSession()
            return game.id
        } catch { self.error = error.localizedDescription; return nil }
    }

    func replace(gameID: UUID, slotID: UUID) {
        do { try engine.replace(gameID: gameID, slotID: slotID); try saveSession() }
        catch { self.error = error.localizedDescription }
    }

    func reset() {
        engine = RandomizerEngine(players: players)
        do { try saveSession() } catch { self.error = error.localizedDescription }
    }

    private func saveSession() throws { try write(engine, name: "session_" + dataset.key) }

    func playerDetails(for player: Player, onlineSearch: Bool = false) async throws -> PlayerDetails {
        if onlineSearch, let cached = onlineDetails[player.url] { return cached }
        if !onlineSearch, let cached = details[player.id], cached.name == player.name { return cached }
        guard onlineSearch || dataset.version.isLive else { throw DataError.missingSnapshot }
        let selection = dataset
        let downloaded = try await service.details(for: player)
        try Task.checkCancellation()
        if onlineSearch { onlineDetails[player.url] = downloaded }
        else if dataset == selection {
            details[player.id] = downloaded
            try write(Array(details.values), name: selection.detailsName)
        }
        return downloaded
    }
}
