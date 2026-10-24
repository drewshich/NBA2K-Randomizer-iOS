import Foundation
import SwiftSoup

enum DataError: LocalizedError {
    case missingSnapshot, invalidData, invalidURL, http(Int)
    var errorDescription: String? {
        switch self {
        case .missingSnapshot: return "Для этого ростера ещё нет сохранённых данных. Загрузите их через интернет."
        case .invalidData: return "Сайт вернул данные в другом формате. Сохранённые ростеры 2K25 и 2K26 доступны без интернета."
        case .invalidURL: return "Не удалось открыть ссылку на игрока."
        case .http(let code): return "Сайт рейтингов недоступен (HTTP \(code)). Попробуйте позже."
        }
    }
}

actor RatingsService {
    private let session: URLSession
    private let base = URL(string: "https://www.2kratings.com")!

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        session = URLSession(configuration: config)
    }

    func roster(era: Era) async throws -> [Player] {
        let path = era == .current ? "/lists/top-100-highest-nba-2k-ratings" : "/lists/top-100-all-time-players"
        return try HTMLRatingsParser.roster(from: await load(base.appendingPathComponent(path)))
    }

    func details(for player: Player) async throws -> PlayerDetails {
        guard let url = URL(string: player.url) else { throw DataError.invalidURL }
        return try HTMLRatingsParser.details(from: await load(url), player: player)
    }

    func search(_ name: String) async throws -> [Player] {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return [] }
        var request = URLRequest(url: base.appendingPathComponent("/wp-admin/admin-ajax.php"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [URLQueryItem(name: "action", value: "ajaxsearchpro_search"),
                           URLQueryItem(name: "aspp", value: name), URLQueryItem(name: "asid", value: "1")]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        try validate(response)
        return try HTMLRatingsParser.search(from: String(decoding: data, as: UTF8.self))
    }

    private func load(_ url: URL) async throws -> String {
        guard url.scheme == "https", ["www.2kratings.com", "2kratings.com"].contains(url.host ?? "") else {
            throw DataError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        try validate(response)
        try Task.checkCancellation()
        return String(decoding: data, as: UTF8.self)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw DataError.invalidData }
        guard (200...299).contains(http.statusCode) else { throw DataError.http(http.statusCode) }
    }
}

enum HTMLRatingsParser {
    private static let base = URL(string: "https://www.2kratings.com")!

    static func absolute(_ link: String) -> String {
        guard !link.isEmpty else { return "" }
        return URL(string: link, relativeTo: base)?.absoluteURL.absoluteString ?? ""
    }

    private static func image(_ element: Element?) throws -> String {
        guard let element else { return "" }
        let lazy = try element.attr("data-src")
        return absolute(try (lazy.isEmpty ? element.attr("src") : lazy).replacingOccurrences(of: "-80x80", with: ""))
    }

    static func heightInCM(_ value: String) -> Int {
        let digits = value.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
        guard digits.count >= 2 else { return digits.first ?? 0 }
        return Int((Double(digits[0] * 12 + digits[1]) * 2.54).rounded())
    }

    static func roster(from html: String) throws -> [Player] {
        let doc = try SwiftSoup.parse(html)
        var players: [Player] = []
        for row in try doc.select("tbody tr").array() {
            guard let entry = try row.select(".entry-font").first(),
                  let link = try entry.select("a").first() else { continue }
            let info = try row.select(".entry-subtext-font").text().components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let ratings = try row.select(".attribute-box").array().map { Int(try $0.text()) ?? 0 }
            guard info.count >= 3, ratings.count >= 3 else { throw DataError.invalidData }
            players.append(Player(id: players.count, name: try entry.text(), team: info[2],
                overall: Rating(value: ratings[0]), threePointRating: Rating(value: ratings[1]),
                dunkRating: Rating(value: ratings[2]), height: heightInCM(info[1]),
                position: info[0].replacingOccurrences(of: " /", with: ","),
                url: absolute(try link.attr("href")), photoUrl: try image(row.select(".entry-bg img").first())))
        }
        guard !players.isEmpty else { throw DataError.invalidData }
        return players
    }

    static func rating(from text: String) -> Rating? {
        let pattern = #"^(.+?)\s+(?:[+-]\d+\s+)?(\d+|-+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(match.range(at: 1), in: text),
              let valueRange = Range(match.range(at: 2), in: text) else { return nil }
        return Rating(value: Int(text[valueRange]) ?? 0, name: String(text[nameRange]))
    }

    static func details(from html: String, player: Player) throws -> PlayerDetails {
        let doc = try SwiftSoup.parse(html)
        var groups: [AttributeGroup] = []
        for card in try doc.select("#nav-attributes .card").array() {
            guard let header = rating(from: try card.select(".card-header").text()) else { continue }
            let parameters = try card.select(".list-group li").array().compactMap { rating(from: try $0.text()) }
            groups.append(AttributeGroup(rating: header, parameters: parameters))
        }
        var badges: [Badge] = []
        for card in try doc.select(".badge-box div.badge-card").array() {
            guard let body = try card.select(".card-body").first() else { continue }
            let parts = body.children().array()
            guard parts.count >= 3 else { continue }
            badges.append(Badge(name: try parts[0].text(), type: try parts[1].text(),
                photoUrl: try image(card.select("img").first()), description: try parts[2].text()))
        }
        guard !groups.isEmpty else { throw DataError.invalidData }
        return PlayerDetails(id: player.id, name: player.name, team: player.team, overall: player.overall,
            height: player.height, position: player.position, photoUrl: player.photoUrl,
            attributes: groups, badges: badges)
    }

    static func search(from content: String) throws -> [Player] {
        struct SearchDTO: Decodable {
            var content: String
            var image: String
            var title: String
            var post_title: String
            var link: String
        }
        guard let start = content.firstIndex(of: "["), let end = content.lastIndex(of: "]"), start <= end else {
            throw DataError.invalidData
        }
        let results = try JSONDecoder().decode([SearchDTO].self, from: Data(content[start...end].utf8))
        return try results.enumerated().compactMap { index, result in
            let title = try SwiftSoup.parse(result.title)
            guard let ratingText = try title.select("span").first()?.text(), let overall = Int(ratingText) else { return nil }
            let team = try SwiftSoup.parse(result.content).select("span").first()?.text() ?? ""
            return Player(id: -index - 1, name: result.post_title, team: team,
                overall: Rating(value: overall), threePointRating: Rating(value: 0), dunkRating: Rating(value: 0),
                height: 0, position: "", url: absolute(result.link),
                photoUrl: absolute(result.image.replacingOccurrences(of: "-80x80", with: "")))
        }
    }
}
