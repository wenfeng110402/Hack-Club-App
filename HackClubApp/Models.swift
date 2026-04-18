import Foundation

struct HCAIdentityResponse: Decodable {
    let identity: HCAIdentity
    let scopes: [String]?
}

struct HCAIdentity: Decodable {
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

struct ExternalVerificationResponse: Decodable {
    let result: String
}

struct HCAUser: Identifiable, Equatable {
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
        isVerifiedMember ? "Verified Member" : "Not Verified"
    }

    var statusSummary: String {
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
        [
            ProfileCardItem(
                title: "Status",
                value: statusTitle,
                detail: statusSummary,
                systemImage: isVerifiedMember ? "checkmark.seal.fill" : "xmark.shield.fill",
                tintHex: isVerifiedMember ? 0x2EA043 : 0xF85149
            ),
            ProfileCardItem(
                title: "Email",
                value: email ?? "Unavailable",
                detail: emailVerified ? "Verified email" : "Email scope unavailable",
                systemImage: "envelope.fill",
                tintHex: 0x58A6FF
            ),
            ProfileCardItem(
                title: "Slack ID",
                value: slackID ?? "Unavailable",
                detail: grantedScopes.contains("slack_id") ? "Slack scope granted" : "Slack scope not granted",
                systemImage: "number.square.fill",
                tintHex: 0xDB61A2
            ),
            ProfileCardItem(
                title: "Identity ID",
                value: id,
                detail: subjectID ?? "No OIDC subject returned",
                systemImage: "person.text.rectangle.fill",
                tintHex: 0x8B949E
            ),
            ProfileCardItem(
                title: "Updated",
                value: updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable",
                detail: "OIDC profile.updated_at",
                systemImage: "clock.fill",
                tintHex: 0xD29922
            ),
            ProfileCardItem(
                title: "Scopes",
                value: grantedScopes.isEmpty ? "Unavailable" : grantedScopes.joined(separator: ", "),
                detail: "\(grantedScopes.count) granted",
                systemImage: "circle.grid.2x2.fill",
                tintHex: 0xA371F7
            )
        ]
    }
}

struct ProfileCardItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tintHex: Int
}

struct OAuthTokenResponse: Decodable {
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
    let title: String
    let items: [YSWSProject]
}

struct YSWSProject: Identifiable, Equatable {
    let id: String
    let title: String
    let link: URL?
    let summary: String
    let publishedAt: Date?
    let deadline: Date?
    let slackChannel: String?

    var daysLeft: Int? {
        guard let deadline else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let end = calendar.startOfDay(for: deadline)
        return calendar.dateComponents([.day], from: today, to: end).day
    }

    var deadlineLabel: String {
        guard let deadline else { return "Rolling" }
        return deadline.formatted(date: .abbreviated, time: .omitted)
    }

    var relativeSummary: String {
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
