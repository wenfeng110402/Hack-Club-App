// clientID 和 clientSecret 现通过环境变量 HACKCLUB_CLIENT_ID 和 HACKCLUB_CLIENT_SECRET 获取，可在 .env 文件中设置并在开发环境加载。
import AuthenticationServices
import Foundation
import UIKit

protocol HackClubAuthServicing {
    func fetchCurrentUser(accessToken: String) async throws -> HCAUser
    func exchangeCodeForToken(code: String) async throws -> OAuthTokenResponse
}

struct HackClubAuthService: HackClubAuthServicing {
    private let session: URLSession
    private let jsonDecoder: JSONDecoder
    private static let clientIDKey = "HACKCLUB_CLIENT_ID"
    private static let clientSecretKey = "HACKCLUB_CLIENT_SECRET"
    private let redirectURI = "hackclub-app://oauth"

    private var clientID: String { ProcessInfo.processInfo.environment[Self.clientIDKey] ?? "" }
    private var clientSecret: String { ProcessInfo.processInfo.environment[Self.clientSecretKey] ?? "" }

    init(session: URLSession = .shared) {
        self.session = session
        self.jsonDecoder = JSONDecoder()
    }

    func fetchCurrentUser(accessToken: String) async throws -> HCAUser {
        let url = URL(string: "https://auth.hackclub.com/api/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        let payload = try jsonDecoder.decode(HCAIdentityResponse.self, from: data)
        let updatedAt = payload.identity.updatedAt.flatMap(Self.iso8601WithFractionalSeconds.date(from:))
            ?? payload.identity.updatedAt.flatMap(Self.iso8601.date(from:))

        let fallbackVerificationStatus = try await fetchFallbackVerificationStatus(for: payload.identity)
        return HCAUser(
            identity: payload.identity,
            scopes: payload.scopes ?? [],
            updatedAt: updatedAt,
            fallbackVerificationStatus: fallbackVerificationStatus
        )
    }

    func exchangeCodeForToken(code: String) async throws -> OAuthTokenResponse {
        let url = URL(string: "https://auth.hackclub.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParameters = [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "code": code
        ]

        request.httpBody = bodyParameters
            .map { key, value in
                let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        return try jsonDecoder.decode(OAuthTokenResponse.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    private func fetchFallbackVerificationStatus(for identity: HCAIdentity) async throws -> String? {
        if let verificationStatus = identity.verificationStatus, !verificationStatus.isEmpty {
            return verificationStatus
        }

        if identity.yswsEligible != nil {
            return nil
        }

        if let id = identity.id, let result = try await fetchExternalVerificationStatus(queryItem: URLQueryItem(name: "idv_id", value: id)), result != "not_found" {
            return result
        }

        if let email = identity.primaryEmail ?? identity.email, let result = try await fetchExternalVerificationStatus(queryItem: URLQueryItem(name: "email", value: email)), result != "not_found" {
            return result
        }

        if let slackID = identity.slackID, let result = try await fetchExternalVerificationStatus(queryItem: URLQueryItem(name: "slack_id", value: slackID)), result != "not_found" {
            return result
        }

        return nil
    }

    private func fetchExternalVerificationStatus(queryItem: URLQueryItem) async throws -> String? {
        var components = URLComponents(string: "https://auth.hackclub.com/api/external/check")!
        components.queryItems = [queryItem]

        guard let url = components.url else { return nil }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)

        let payload = try jsonDecoder.decode(ExternalVerificationResponse.self, from: data)
        return payload.result
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

protocol YSWSFeedServicing {
    func fetchFeed() async throws -> YSWSFeed
}

struct YSWSFeedService: YSWSFeedServicing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchFeed() async throws -> YSWSFeed {
        let url = URL(string: "https://ysws.hackclub.com/feed.xml")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let parser = YSWSFeedXMLParser()
        return try parser.parse(data: data)
    }
}

final class YSWSFeedXMLParser: NSObject, XMLParserDelegate {
    private var channelTitle = ""
    private var items: [YSWSProject] = []
    private var currentText = ""
    private var currentItem = FeedItemDraft()
    private var isInsideItem = false

    func parse(data: Data) throws -> YSWSFeed {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self

        guard xmlParser.parse() else {
            throw xmlParser.parserError ?? FeedXMLError.invalidData
        }

        return YSWSFeed(title: channelTitle, items: items)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentText = ""

        if elementName == "item" {
            currentItem = FeedItemDraft()
            isInsideItem = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInsideItem {
            switch elementName {
            case "title":
                currentItem.title = text
            case "link":
                currentItem.link = text
            case "guid":
                currentItem.guid = text
            case "pubDate":
                currentItem.pubDate = text
            case "description":
                currentItem.descriptionHTML = text
            case "item":
                if let project = currentItem.makeProject() {
                    items.append(project)
                }
                isInsideItem = false
            default:
                break
            }
        } else if elementName == "title", !text.isEmpty {
            channelTitle = text
        }

        currentText = ""
    }
}

private struct FeedItemDraft {
    var title = ""
    var link = ""
    var guid = ""
    var pubDate = ""
    var descriptionHTML = ""

    func makeProject() -> YSWSProject? {
        guard !title.isEmpty else { return nil }

        let summary = descriptionHTML.captureFirst(pattern: "<p>(.*?)</p>")?
            .strippingHTML
            .decodedHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "No summary available."

        let deadlineText = descriptionHTML.captureFirst(pattern: "Deadline:</strong>\\s*([^<]+)")
        let slackText = descriptionHTML.captureFirst(pattern: ">#([^<]+)<")
        let deadline = deadlineText.flatMap(Self.deadlineFormatter.date(from:))
        let publishedAt = Self.pubDateFormatter.date(from: pubDate)

        return YSWSProject(
            id: guid.isEmpty ? title : guid,
            title: title,
            link: URL(string: link),
            summary: summary,
            publishedAt: publishedAt,
            deadline: deadline,
            slackChannel: slackText
        )
    }

    private static let deadlineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter
    }()

    private static let pubDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

private extension String {
    func captureFirst(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return String(self[range])
    }

    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    var decodedHTMLEntities: String {
        let data = Data(utf8)
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else {
            return self
        }

        return attributed.string
    }
}

enum HapticManager {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    static func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let activeScene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        if let window = activeScene?.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        if let scene = activeScene {
            return ASPresentationAnchor(windowScene: scene)
        }
        if let fallbackScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return ASPresentationAnchor(windowScene: fallbackScene)
        }
        preconditionFailure("No active window scene available for authentication presentation.")
    }
}
