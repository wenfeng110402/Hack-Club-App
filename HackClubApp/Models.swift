import Foundation

// MARK: - API 返回结构
struct HCAIdentityResponse: Decodable {
    // `/api/v1/me` 返回的用户主体数据。
    let identity: HCAIdentity

    // 后端同时会返回当前授权拿到的 scopes。
    let scopes: [String]?
}

struct HCAIdentity: Decodable {
    // 下面这些字段都对应 Auth 接口返回的 JSON 字段。
    let id: String?
    let sub: String?
    let name: String?
    let givenName: String?
    let familyName: String?
    let nickname: String?
    let email: String?
    let emailVerified: Bool?
    let primaryEmail: String?
    let slackID: String?
    let verificationStatus: String?
    let yswsEligible: Bool?
    let updatedAt: String?
    let label: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sub
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case nickname
        case email
        case emailVerified = "email_verified"
        case primaryEmail = "primary_email"
        case slackID = "slack_id"
        case verificationStatus = "verification_status"
        case yswsEligible = "ysws_eligible"
        case updatedAt = "updated_at"
        case label
    }
}

// MARK: - 由接口数据派生出的用户状态
struct ExternalVerificationResponse: Decodable {
    // 外部验证接口只返回一个结果字符串。
    let result: String
}

struct HCAUser: Identifiable, Equatable {
    // 这些字段是给 UI 直接使用的“整理后数据”。
    let id: String
    let subjectID: String?
    let displayName: String
    let nickname: String?
    let email: String?
    let emailVerified: Bool
    let slackID: String?
    let verificationStatus: String?
    let yswsEligible: Bool
    let updatedAt: Date?
    let label: String?
    let grantedScopes: [String]

    init(identity: HCAIdentity, scopes: [String], updatedAt: Date?, fallbackVerificationStatus: String? = nil) {
        // 有些接口字段可能为空，所以这里先做兜底处理。
        let resolvedID = identity.id ?? identity.sub ?? UUID().uuidString
        let resolvedEmail = identity.primaryEmail ?? identity.email
        let resolvedName = identity.name
            ?? [identity.givenName, identity.familyName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .nilIfEmpty
            ?? identity.nickname
            ?? resolvedEmail
            ?? "Hack Clubber"

        self.id = resolvedID
        self.subjectID = identity.sub
        self.displayName = resolvedName
        self.nickname = identity.nickname
        self.email = resolvedEmail
        self.emailVerified = identity.emailVerified ?? false
        self.slackID = identity.slackID
        self.verificationStatus = identity.verificationStatus ?? fallbackVerificationStatus
        self.yswsEligible = identity.yswsEligible ?? false
        self.updatedAt = updatedAt
        self.label = identity.label
        self.grantedScopes = scopes
    }

    var verificationSignals: [String] {
        // 这个数组用于首页的大卡片右上角显示信号数量。
        var signals: [String] = []

        if yswsEligible {
            signals.append("ysws_eligible")
        }

        if let verificationStatus {
            let normalized = verificationStatus.lowercased()
            if normalized.contains("verified") || normalized == "pending" || normalized == "needs_submission" || normalized == "ineligible" || normalized == "rejected" {
                signals.append("verification_status:\(verificationStatus)")
            }
        }

        if let label, label.lowercased().contains("verified") {
            signals.append("label:\(label)")
        }

        if emailVerified {
            signals.append("email_verified")
        }

        return signals
    }

    var isVerifiedMember: Bool {
        // 只要满足任一验证条件，就认为用户是 verified member。
        if yswsEligible {
            return true
        }

        if let verificationStatus {
            let normalized = verificationStatus.lowercased()
            if normalized.contains("verified") || normalized == "verified_eligible" || normalized == "verified_but_over_18" {
                return true
            }
        }

        if let label, label.lowercased().contains("verified") {
            return true
        }

        return emailVerified
    }

    var statusTitle: String {
        // 首页顶部大卡片显示的状态标题。
        isVerifiedMember ? "Verified Member" : "Not Verified"
    }

    var statusSummary: String {
        // 根据 verification_status 生成更适合界面展示的文案。
        if let verificationStatus, !verificationStatus.isEmpty {
            switch verificationStatus.lowercased() {
            case "verified", "verified_eligible":
                return "Eligible for YSWS"
            case "verified_but_over_18":
                return "Verified but over 18"
            case "pending":
                return "Verification under review"
            case "needs_submission":
                return "Verification not started"
            case "ineligible", "rejected":
                return "Verification rejected"
            default:
                return verificationStatus.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }

        if emailVerified {
            return "Confirmed via email scope"
        }

        return "No verification signal returned"
    }

    var profileRows: [ProfileCardItem] {
        // 这里定义首页下方的小卡片顺序和内容。
        [
            ProfileCardItem(
                title: "YSWS Eligible",
                value: yswsEligible ? "Eligible for YSWS" : "Not Eligible",
                detail: yswsEligible ? "ysws_eligible returned true" : "ysws_eligible returned false",
                systemImage: yswsEligible ? "checkmark.seal.fill" : "xmark.shield.fill",
                tintHex: yswsEligible ? 0x2EA043 : 0xF85149,
                copyValue: yswsEligible ? "Eligible for YSWS" : "Not Eligible"
            ),
            ProfileCardItem(
                title: "Hackatime",
                value: "Unavailable",
                detail: "Currently unavailable",
                systemImage: "timer",
                tintHex: 0x58A6FF,
                copyValue: nil
            ),
            ProfileCardItem(
                title: "Slack ID",
                value: slackID ?? "Unavailable",
                detail: grantedScopes.contains("slack_id") ? "Slack scope granted" : "Slack scope not granted",
                systemImage: "number.square.fill",
                tintHex: 0xDB61A2,
                copyValue: slackID
            ),
            ProfileCardItem(
                title: "Identity ID",
                value: id,
                detail: subjectID ?? "No OIDC subject returned",
                systemImage: "person.text.rectangle.fill",
                tintHex: 0x8B949E,
                copyValue: id
            ),
            ProfileCardItem(
                title: "Mail",
                value: "will come",
                detail: "will come",
                systemImage: "envelope.fill",
                tintHex: 0xD29922,
                copyValue: nil
            ),
            ProfileCardItem(
                title: "Scopes",
                value: grantedScopes.isEmpty ? "Unavailable" : grantedScopes.joined(separator: ", "),
                detail: "\(grantedScopes.count) granted",
                systemImage: "circle.grid.2x2.fill",
                tintHex: 0xA371F7,
                copyValue: grantedScopes.isEmpty ? nil : grantedScopes.joined(separator: ", ")
            )
        ]
    }
}

// MARK: - 小卡片数据模型
struct ProfileCardItem: Identifiable, Equatable {
    // SwiftUI 的 ForEach 需要稳定的 id。
    let id = UUID()
    // 卡片标题，例如 Slack ID。
    let title: String
    // 卡片上真正显示的值。
    let value: String
    // 卡片下方的补充说明。
    let detail: String
    // 用于左上角图标的 SF Symbol 名称。
    let systemImage: String
    // 图标颜色。
    let tintHex: Int
    // 长按复制时真正写入剪贴板的内容。
    let copyValue: String?

    init(
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        tintHex: Int,
        copyValue: String? = nil
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.tintHex = tintHex
        self.copyValue = copyValue
    }
}

struct OAuthTokenResponse: Decodable {
    // OAuth 换回来的 access token。
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

struct YSWSFeed: Equatable {
    // feed 的标题和内容项。
    let title: String
    let items: [YSWSProject]
}

struct YSWSProject: Identifiable, Equatable {
    // 每个项目在列表里的唯一标识。
    let id: String
    // 项目标题。
    let title: String
    // 外链地址。
    let link: URL?
    // 项目简介。
    let summary: String
    // 发布日期。
    let publishedAt: Date?
    // 截止日期。
    let deadline: Date?
    // 相关 Slack 频道名。
    let slackChannel: String?

    var daysLeft: Int? {
        // 计算从今天到截止日期还有多少天。
        guard let deadline else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: deadline)
        return calendar.dateComponents([.day], from: today, to: end).day
    }

    var deadlineLabel: String {
        // 没有截止日期时显示 Rolling。
        guard let deadline else { return "Rolling" }
        return deadline.formatted(date: .abbreviated, time: .omitted)
    }

    var relativeSummary: String {
        // 根据天数生成更口语化的描述。
        guard let daysLeft else { return "No fixed deadline" }
        if daysLeft < 0 { return "Ended \(-daysLeft)d ago" }
        if daysLeft == 0 { return "Ends today" }
        return "\(daysLeft)d left"
    }
}

enum FeedXMLError: Error {
    case invalidData
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
