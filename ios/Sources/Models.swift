import Foundation

enum GameVersion: String, CaseIterable, Codable, Identifiable {
    case k25 = "2K25", k26 = "2K26", k27 = "2K27"
    var id: String { rawValue }
    var isLive: Bool { self == .k27 }
    var title: String { isLive ? "2K27 · онлайн" : rawValue }
}

enum Era: String, CaseIterable, Codable, Identifiable {
    case current = "current", allTime = "all_time"
    var id: String { rawValue }
    var title: String { self == .current ? "Текущие" : "Легенды" }
}

enum Position: String, CaseIterable, Codable, Identifiable {
    case pg = "PG", sg = "SG", sf = "SF", pf = "PF", c = "C"
    var id: String { rawValue }
}

struct Dataset: Codable, Equatable {
    var version: GameVersion = .k26
    var era: Era = .current
    var key: String { "\(era.rawValue)_\(version.rawValue.lowercased())" }
    var rosterName: String { "\(era.rawValue)_players_\(version.rawValue.lowercased())" }
    var detailsName: String { "\(era.rawValue)_players_details_\(version.rawValue.lowercased())" }
}

struct Rating: Codable, Hashable {
    var value: Int
    var color: Int? = nil
    var name: String? = nil
}

struct Player: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var team: String
    var overall: Rating
    var threePointRating: Rating
    var dunkRating: Rating
    var height: Int
    var position: String
    var url: String
    var photoUrl: String

    func supports(_ position: Position) -> Bool {
        self.position.components(separatedBy: CharacterSet(charactersIn: ",/ "))
            .contains(position.rawValue)
    }
}

struct AttributeGroup: Codable, Hashable {
    var rating: Rating
    var parameters: [Rating]
}

struct Badge: Codable, Hashable {
    var name: String
    var type: String
    var photoUrl: String
    var description: String
}

struct PlayerDetails: Codable, Identifiable {
    var id: Int
    var name: String
    var team: String
    var overall: Rating
    var height: Int
    var position: String
    var photoUrl: String
    var attributes: [AttributeGroup]
    var badges: [Badge]
}

enum SortField: String, CaseIterable, Identifiable {
    case overall = "Рейтинг", name = "Имя", team = "Команда"
    case threePoint = "Трёхочковые", dunk = "Данк", height = "Рост"
    var id: String { rawValue }
}

struct RosterFilter {
    var name = ""
    var team = ""
    var position: Position? = nil
    var sort: SortField = .overall
    var ascending = false

    func apply(to players: [Player]) -> [Player] {
        players.filter {
            (name.isEmpty || $0.name.localizedCaseInsensitiveContains(name)) &&
            (team.isEmpty || $0.team == team) &&
            (position == nil || $0.supports(position!))
        }.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case .name: comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .team: comparison = lhs.team.localizedCaseInsensitiveCompare(rhs.team)
            default:
                let left = value(of: lhs), right = value(of: rhs)
                comparison = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private func value(of player: Player) -> Int {
        switch sort {
        case .threePoint: return player.threePointRating.value
        case .dunk: return player.dunkRating.value
        case .height: return player.height
        default: return player.overall.value
        }
    }
}

struct DraftSlot: Codable, Identifiable, Equatable {
    var id = UUID()
    var team: Int
    var position: Position?
    var player: Player
}

struct Replacement: Codable, Identifiable, Equatable {
    var id = UUID()
    var oldPlayer: Player
    var newPlayer: Player
}

struct DraftGame: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var teamsCount: Int
    var slots: [DraftSlot]
    var replacements: [Replacement] = []
}

enum RandomizerError: LocalizedError {
    case noPlayers, notEnough, positionsCount, invalidOptions
    case missingPosition(Position), historyReadOnly

    var errorDescription: String? {
        switch self {
        case .noPlayers: return "Сначала загрузите ростер в настройках."
        case .notEnough: return "В колоде не хватает игроков. Начните новую колоду."
        case .positionsCount: return "Выберите столько позиций, сколько игроков в одной команде, или отключите позиции."
        case .invalidOptions: return "Можно выбрать 1–5 игроков и одну или две команды."
        case .missingPosition(let position): return "Не хватает игроков на позицию \(position.rawValue). Измените позиции или начните новую колоду."
        case .historyReadOnly: return "Менять игроков можно только в последней игре."
        }
    }
}

struct RandomizerEngine: Codable {
    private(set) var pool: [Player]
    private(set) var games: [DraftGame] = []
    private(set) var total: Int
    var usedCount: Int { total - pool.count }

    init(players: [Player], shuffle: Bool = true) {
        pool = shuffle ? players.shuffled() : players
        total = players.count
    }

    mutating func draw(playersPerTeam: Int, teamsCount: Int, positions: [Position]) throws -> DraftGame {
        guard (1...5).contains(playersPerTeam), (1...2).contains(teamsCount) else {
            throw RandomizerError.invalidOptions
        }
        let uniquePositions = Position.allCases.filter { positions.contains($0) }
        guard uniquePositions.isEmpty || uniquePositions.count == playersPerTeam else {
            throw RandomizerError.positionsCount
        }
        guard total > 0 else { throw RandomizerError.noPlayers }
        let count = playersPerTeam * teamsCount
        guard pool.count >= count else { throw RandomizerError.notEnough }

        let required: [Position?] = uniquePositions.isEmpty
            ? Array(repeating: nil, count: count)
            : uniquePositions.flatMap { Array(repeating: Optional($0), count: teamsCount) }

        // Match all positions before changing the deck. Flexible players may move
        // between slots so that a valid line-up is not rejected by a greedy draw.
        let candidates = pool
        var playerToSlot: [Int: Int] = [:]
        func assign(_ slot: Int, visited: inout Set<Int>) -> Bool {
            for index in candidates.indices {
                if let position = required[slot], !candidates[index].supports(position) { continue }
                guard visited.insert(index).inserted else { continue }
                if let previous = playerToSlot[index], !assign(previous, visited: &visited) { continue }
                playerToSlot[index] = slot
                return true
            }
            return false
        }

        for slot in 0..<count {
            var visited = Set<Int>()
            guard assign(slot, visited: &visited) else {
                throw RandomizerError.missingPosition(required[slot] ?? .pg)
            }
        }
        var indices = Array(repeating: 0, count: count)
        for (playerIndex, slot) in playerToSlot { indices[slot] = playerIndex }
        let slots = (0..<count).map {
            DraftSlot(team: $0 % teamsCount, position: required[$0], player: pool[indices[$0]])
        }
        let selected = Set(indices)
        pool = pool.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
        let game = DraftGame(teamsCount: teamsCount, slots: slots)
        games.append(game)
        return game
    }

    mutating func replace(gameID: UUID, slotID: UUID) throws {
        guard let gameIndex = games.indices.last, games[gameIndex].id == gameID,
              let slotIndex = games[gameIndex].slots.firstIndex(where: { $0.id == slotID }) else {
            throw RandomizerError.historyReadOnly
        }
        let slot = games[gameIndex].slots[slotIndex]
        guard let index = pool.firstIndex(where: { slot.position == nil || $0.supports(slot.position!) }) else {
            if let position = slot.position { throw RandomizerError.missingPosition(position) }
            throw RandomizerError.notEnough
        }
        let replacement = pool.remove(at: index)
        games[gameIndex].replacements.append(Replacement(oldPlayer: slot.player, newPlayer: replacement))
        games[gameIndex].slots[slotIndex].player = replacement
    }

    func isValid(for players: [Player]) -> Bool {
        let rosterIDs = Set(players.map(\.id))
        let consumed = games.flatMap { $0.slots.map(\.player) + $0.replacements.map(\.oldPlayer) }
        let allIDs = pool.map(\.id) + consumed.map(\.id)
        let roster = Dictionary(players.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        return total == players.count && allIDs.count == total &&
            Set(allIDs).count == total && Set(allIDs) == rosterIDs &&
            (pool + consumed).allSatisfy { roster[$0.id] == $0 }
    }
}
