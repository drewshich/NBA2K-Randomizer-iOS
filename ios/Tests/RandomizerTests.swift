import XCTest
@testable import NBA2KRandomizer

final class RandomizerTests: XCTestCase {
    private func player(_ id: Int, _ position: String) -> Player {
        Player(id: id, name: "Player \(id)", team: "TEST", overall: Rating(value: 90),
               threePointRating: Rating(value: 80), dunkRating: Rating(value: 70),
               height: 200, position: position, url: "https://www.2kratings.com/player-\(id)", photoUrl: "")
    }

    func testAllBundledRostersAndDetailsMatch() throws {
        for version in [GameVersion.k25, .k26] {
            for era in Era.allCases {
                let dataset = Dataset(version: version, era: era)
                let players = try SnapshotLoader.decode([Player].self, name: dataset.rosterName)
                let details = try SnapshotLoader.decode([PlayerDetails].self, name: dataset.detailsName)
                XCTAssertEqual(players.count, 100, dataset.key)
                XCTAssertEqual(details.count, players.count, dataset.key)
                XCTAssertEqual(Set(players.map(\.id)).count, players.count)
                let byID = Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) })
                for player in players {
                    XCTAssertEqual(byID[player.id]?.name, player.name)
                    XCTAssertFalse(byID[player.id]?.attributes.isEmpty ?? true)
                    XCTAssertTrue(player.url.hasPrefix("https://"))
                }
            }
        }
    }

    func testDrawDoesNotRepeatAcrossGames() throws {
        let players = try SnapshotLoader.decode([Player].self, name: Dataset().rosterName)
        var engine = RandomizerEngine(players: players)
        var seen = Set<Int>()
        for _ in 0..<10 {
            let game = try engine.draw(playersPerTeam: 5, teamsCount: 2, positions: [])
            XCTAssertEqual(game.slots.filter { $0.team == 0 }.count, 5)
            XCTAssertEqual(game.slots.filter { $0.team == 1 }.count, 5)
            for slot in game.slots { XCTAssertTrue(seen.insert(slot.player.id).inserted) }
        }
        XCTAssertEqual(seen.count, 100)
        XCTAssertTrue(engine.pool.isEmpty)
        XCTAssertTrue(engine.isValid(for: players))
        XCTAssertThrowsError(try engine.draw(playersPerTeam: 1, teamsCount: 1, positions: []))
    }

    func testFlexiblePlayerCanMoveToMakeValidLineup() throws {
        var engine = RandomizerEngine(players: [player(0, "PG, SG"), player(1, "PG")], shuffle: false)
        let game = try engine.draw(playersPerTeam: 2, teamsCount: 1, positions: [.pg, .sg])
        XCTAssertEqual(game.slots[0].player.id, 1)
        XCTAssertEqual(game.slots[1].player.id, 0)
    }

    func testFailedPositionDrawIsTransactional() throws {
        var engine = RandomizerEngine(players: [player(0, "PG"), player(1, "PG")], shuffle: false)
        let pool = engine.pool
        XCTAssertThrowsError(try engine.draw(playersPerTeam: 2, teamsCount: 1, positions: [.pg, .c]))
        XCTAssertEqual(engine.pool, pool)
        XCTAssertTrue(engine.games.isEmpty)
        XCTAssertThrowsError(try engine.draw(playersPerTeam: 2, teamsCount: 1, positions: [.pg]))
        XCTAssertEqual(engine.pool, pool)
    }

    func testReplacementPreservesPositionAndPersistence() throws {
        let players = [player(0, "PG"), player(1, "SG"), player(2, "PG"), player(3, "SG")]
        var engine = RandomizerEngine(players: players, shuffle: false)
        let game = try engine.draw(playersPerTeam: 1, teamsCount: 1, positions: [.pg])
        try engine.replace(gameID: game.id, slotID: game.slots[0].id)
        XCTAssertEqual(engine.games[0].slots[0].player.id, 2)
        XCTAssertEqual(engine.games[0].replacements[0].oldPlayer.id, 0)
        XCTAssertEqual(engine.usedCount, 2)
        XCTAssertTrue(engine.isValid(for: players))
        let restored = try JSONDecoder().decode(RandomizerEngine.self, from: JSONEncoder().encode(engine))
        XCTAssertEqual(restored.games, engine.games)
        XCTAssertEqual(restored.pool, engine.pool)
        XCTAssertTrue(restored.isValid(for: players))
    }

    func testHistoryCannotBeEdited() throws {
        var engine = RandomizerEngine(players: (0..<5).map { player($0, "PG") }, shuffle: false)
        let first = try engine.draw(playersPerTeam: 1, teamsCount: 1, positions: [])
        _ = try engine.draw(playersPerTeam: 1, teamsCount: 1, positions: [])
        let pool = engine.pool
        XCTAssertThrowsError(try engine.replace(gameID: first.id, slotID: first.slots[0].id))
        XCTAssertEqual(engine.pool, pool)
    }

    func testPositionFilterMatchesWholePosition() {
        let players = [player(0, "PG, SG"), player(1, "C")]
        var filter = RosterFilter()
        filter.position = .c
        XCTAssertEqual(filter.apply(to: players).map(\.id), [1])
        filter.position = .sg
        XCTAssertEqual(filter.apply(to: players).map(\.id), [0])
        filter.name = "player 1"
        XCTAssertTrue(filter.apply(to: players).isEmpty)
    }

    func testHTMLRosterAndAttributeParser() throws {
        let html = """
        <table><tbody><tr><td class="entry-bg"><img data-src="/photo-80x80.png"></td>
        <td><div class="entry-font"><a href="/example">Example Player</a></div>
        <div class="entry-subtext-font">PG / SG | 6' 2\" | BOS</div></td>
        <td class="attribute-box">94</td><td class="attribute-box">88</td><td class="attribute-box">65</td>
        </tr></tbody></table>
        """
        let result = try HTMLRatingsParser.roster(from: html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].height, 188)
        XCTAssertEqual(result[0].photoUrl, "https://www.2kratings.com/photo.png")
        XCTAssertTrue(result[0].supports(.sg))
        XCTAssertEqual(HTMLRatingsParser.rating(from: "Three-Point Shot +2 95")?.value, 95)
        XCTAssertEqual(HTMLRatingsParser.rating(from: "Post Control -3 81")?.name, "Post Control")
        XCTAssertEqual(HTMLRatingsParser.rating(from: "Post Hook --")?.value, 0)
        XCTAssertNil(HTMLRatingsParser.rating(from: "no rating"))
        XCTAssertThrowsError(try HTMLRatingsParser.roster(from: "<html>Changed site</html>"))
    }

    func testDetailsAndSearchParser() throws {
        let html = """
        <div id="nav-attributes"><div class="card"><div class="card-header">Playmaking 90</div>
        <ul class="list-group"><li>Pass IQ 95</li><li>Ball Handle +1 87</li></ul></div></div>
        <div class="badge-box"><div class="badge-card"><img data-src="/badge.png">
        <div class="card-body"><h4>Dimer</h4><p>Playmaking</p><p>Passes improve shots.</p></div></div></div>
        """
        let details = try HTMLRatingsParser.details(from: html, player: player(5, "PG"))
        XCTAssertEqual(details.attributes[0].parameters.count, 2)
        XCTAssertEqual(details.badges[0].name, "Dimer")
        let search = #"prefix [{"content":"<span>BOS</span>","image":"/photo-80x80.png","title":"<span>94</span>","post_title":"Example","link":"/example"}] suffix"#
        let result = try HTMLRatingsParser.search(from: search)
        XCTAssertEqual(result[0].name, "Example")
        XCTAssertEqual(result[0].overall.value, 94)
        XCTAssertEqual(result[0].id, -1)
    }
}
