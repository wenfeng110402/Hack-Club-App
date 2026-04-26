// clientID 和 clientSecret 通过环境变量读取，避免把敏感信息硬编码进仓库。
import AuthenticationServices
import Foundation
import UIKit

// MARK: - Hack Club 登录服务
protocol HackClubAuthServicing {
    // 拉取当前登录用户的资料。
    func fetchCurrentUser(accessToken: String) async throws -> HCAUser

    // 用 OAuth 授权码换取 access token。
    func exchangeCodeForToken(code: String) async throws -> OAuthTokenResponse
}

struct HackClubAuthService: HackClubAuthServicing {
    // 所有网络请求都通过同一个 URLSession 发出。
    private let session: URLSession
    // JSON 解码器，用来把接口返回值转成 Swift 模型。
    private let jsonDecoder: JSONDecoder
    // 环境变量 key。
    private static let clientIDKey = "HACKCLUB_CLIENT_ID"
    private static let clientSecretKey = "HACKCLUB_CLIENT_SECRET"
    // OAuth 回调地址。
    private let redirectURI = "hackclub-app://oauth"

    private var clientID: String { ProcessInfo.processInfo.environment[Self.clientIDKey] ?? "" }
    private var clientSecret: String { ProcessInfo.processInfo.environment[Self.clientSecretKey] ?? "" }

    init(session: URLSession = .shared) {
        self.session = session
        self.jsonDecoder = JSONDecoder()
    }

    func fetchCurrentUser(accessToken: String) async throws -> HCAUser {
        // /api/v1/me 会返回当前用户的身份信息和 scopes。
        let url = URL(string: "https://auth.hackclub.com/api/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response: response)

        // 先解码成原始身份结构，再整理成界面直接使用的数据。
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
        // token 接口使用 POST + form-urlencoded。
        let url = URL(string: "https://auth.hackclub.com/oauth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // 没有配置环境变量就直接报错，避免请求发出去才失败。
        guard !clientID.isEmpty, !clientSecret.isEmpty else {
            throw NSError(
                domain: "HackClubAuth",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing client credentials. Please configure HACKCLUB_CLIENT_ID and HACKCLUB_CLIENT_SECRET environment variables."]
            )
        }

        // 把 OAuth 所需参数组装成表单 body。
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

        // 保留调试信息，方便本地排查 token exchange 问题。
        if let httpResponse = response as? HTTPURLResponse {
            print("Token exchange response status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response body: \(responseString)")
            }
        }

        try validate(response: response)
        return try jsonDecoder.decode(OAuthTokenResponse.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        // 只有 2xx 才算成功。
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
    }

    private func fetchFallbackVerificationStatus(for identity: HCAIdentity) async throws -> String? {
        // 如果接口已经直接返回了 verification_status，就优先使用它。
        if let verificationStatus = identity.verificationStatus, !verificationStatus.isEmpty {
            return verificationStatus
        }

        // 如果已经明确给了 yswsEligible，就不再额外查外部验证接口。
        if identity.yswsEligible != nil {
            return nil
        }

        // 依次用 id / email / slack_id 去外部验证接口兜底查询。
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
        // 构造外部检查接口的 URL。
        var components = URLComponents(string: "https://auth.hackclub.com/api/external/check")!
        components.queryItems = [queryItem]

        guard let url = components.url else { return nil }

        let (data, response) = try await session.data(from: url)
        try validate(response: response)

        let payload = try jsonDecoder.decode(ExternalVerificationResponse.self, from: data)
        return payload.result
    }

    // 解析带小数秒的 ISO8601 时间。
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // 解析带小数秒的 ISO8601 时间。
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - YSWS Feed 服务
protocol YSWSFeedServicing {
    // 拉取 YSWS feed。
    func fetchFeed() async throws -> YSWSFeed
}

struct YSWSFeedService: YSWSFeedServicing {
    // 同样通过 URLSession 请求网络。
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchFeed() async throws -> YSWSFeed {
        // YSWS 项目源数据来自 feed.xml。
        let url = URL(string: "https://ysws.hackclub.com/feed.xml")!
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        // XML 不是 JSON，需要单独的解析器来处理。
        let parser = YSWSFeedXMLParser()
        return try parser.parse(data: data)
    }
}

// MARK: - XML Feed 解析器
final class YSWSFeedXMLParser: NSObject, XMLParserDelegate {
    // 解析过程中先把字段暂存在这些缓存里。
    private var channelTitle = ""
    private var items: [YSWSProject] = []
    private var currentText = ""
    private var currentItem = FeedItemDraft()
    private var isInsideItem = false

    func parse(data: Data) throws -> YSWSFeed {
        // 把 XML 数据交给系统 XMLParser，再通过 delegate 逐步解析。
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self

        guard xmlParser.parse() else {
            throw xmlParser.parserError ?? FeedXMLError.invalidData
        }

        return YSWSFeed(title: channelTitle, items: items)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        // 每次进入新节点时都重置文本缓存。
        currentText = ""

        if elementName == "item" {
            // item 节点代表一条新的项目内容。
            currentItem = FeedItemDraft()
            isInsideItem = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        // XML 文本可能分多次回调，所以这里要持续拼接。
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
                // 一个 item 结束后，尝试把它转成真正的项目模型。
                if let project = currentItem.makeProject() {
                    items.append(project)
                }
                isInsideItem = false
            default:
                break
            }
        } else if elementName == "title", !text.isEmpty {
            // 频道标题只在 item 外面读取。
            channelTitle = text
        }

        currentText = ""
    }
}

// MARK: - XML 解析辅助结构
private struct FeedItemDraft {
    // 暂存单条 feed 的原始字段，等收集完整后再转成 YSWSProject。
    var title = ""
    var link = ""
    var guid = ""
    var pubDate = ""
    var descriptionHTML = ""

    func makeProject() -> YSWSProject? {
        // 没标题就不是有效条目。
        guard !title.isEmpty else { return nil }

        // 从 HTML 描述中提取正文摘要。
        let summary = descriptionHTML.captureFirst(pattern: "<p>(.*?)</p>")?
            .strippingHTML
            .decodedHTMLEntities
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "No summary available."

        let deadlineText = descriptionHTML.captureFirst(pattern: "Deadline:</strong>\\s*([^<]+)")
        let slackText = descriptionHTML.captureFirst(pattern: ">#([^<]+)<")
        let deadline = deadlineText.flatMap(Self.deadlineFormatter.date(from:))
        let publishedAt = Self.pubDateFormatter.date(from: pubDate)

        // 把原始 XML 数据整理成界面直接可用的项目模型。
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

// MARK: - 字符串解析辅助
private extension String {
    func captureFirst(pattern: String) -> String? {
        // 用正则抓取第一个匹配分组。
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self) else {
            return nil
        }

        return String(self[range])
    }

    var strippingHTML: String {
        // 去掉 HTML 标签，只保留纯文本。
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    var decodedHTMLEntities: String {
        // 把 &amp;、&lt; 这类实体还原成人类可读文本。
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

// MARK: - 触感反馈
enum HapticManager {
    // 轻量选择反馈，比如切换 tab、复制成功。
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // 普通冲击反馈，适合按钮点击。
    static func impact(style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    // 成功 / 警告 / 失败这类结果反馈。
    static func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

// MARK: - OAuth 展示锚点
final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // 找到当前前台窗口，供系统授权页弹出使用。
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
