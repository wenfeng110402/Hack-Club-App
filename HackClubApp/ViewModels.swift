import Combine
import Foundation

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var user: HCAUser?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let authService: HackClubAuthServicing

    init() {
        self.authService = HackClubAuthService()
    }

    init(authService: HackClubAuthServicing) {
        self.authService = authService
    }

    func refreshUser(accessToken: String) async {
        guard !accessToken.isEmpty else {
            user = nil
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            user = try await authService.fetchCurrentUser(accessToken: accessToken)
        } catch {
            user = nil
            errorMessage = "Failed to load your Hack Club profile."
        }

        isLoading = false
    }

    func clear() {
        user = nil
        errorMessage = nil
    }
}

@MainActor
final class YSWSDashboardViewModel: ObservableObject {
    @Published private(set) var projects: [YSWSProject] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let feedService: YSWSFeedServicing

    init() {
        self.feedService = YSWSFeedService()
    }

    init(feedService: YSWSFeedServicing) {
        self.feedService = feedService
    }

    func loadIfNeeded() async {
        guard projects.isEmpty else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        do {
            let feed = try await feedService.fetchFeed()
            let activeProjects = feed.items.filter { project in
                guard let daysLeft = project.daysLeft else { return true }
                return daysLeft >= 0
            }

            projects = activeProjects.sorted { lhs, rhs in
                switch (lhs.publishedAt, rhs.publishedAt) {
                case let (leftDate?, rightDate?) where leftDate != rightDate:
                    return leftDate > rightDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return (lhs.deadline ?? .distantFuture) < (rhs.deadline ?? .distantFuture)
                }
            }
        } catch {
            errorMessage = "Failed to load YSWS feed."
        }

        isLoading = false
    }
}
