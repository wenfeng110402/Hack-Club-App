import Combine
import Foundation

// MARK: - 首页用户状态
@MainActor
final class SessionViewModel: ObservableObject {
    // 当前登录用户的数据，由 API 拉取后写入这里。
    @Published private(set) var user: HCAUser?

    // 页面是否正在加载用户信息。
    @Published private(set) var isLoading = false

    // 加载失败时给界面显示的错误文案。
    @Published private(set) var errorMessage: String?

    // 通过协议注入服务，方便以后测试和替换实现。
    private let authService: HackClubAuthServicing

    init() {
        self.authService = HackClubAuthService()
    }

    init(authService: HackClubAuthServicing) {
        self.authService = authService
    }

    func refreshUser(accessToken: String) async {
        // 没有 token 时说明没登录，直接清空状态即可。
        guard !accessToken.isEmpty else {
            user = nil
            errorMessage = nil
            return
        }

        // 开始加载时先清掉旧错误，避免界面显示过期提示。
        isLoading = true
        errorMessage = nil

        do {
            // 从 Hack Club Auth 拉取当前用户资料。
            user = try await authService.fetchCurrentUser(accessToken: accessToken)
        } catch {
            // 失败时只给用户一个通用提示，避免暴露过多实现细节。
            user = nil
            errorMessage = "Failed to load your Hack Club profile."
        }

        isLoading = false
    }

    func clear() {
        // 退出登录时，把页面上保留的用户状态一起清掉。
        user = nil
        errorMessage = nil
    }
}

// MARK: - YSWS 列表状态
@MainActor
final class YSWSDashboardViewModel: ObservableObject {
    // 解析后的 YSWS 项目列表。
    @Published private(set) var projects: [YSWSProject] = []

    // 拉取 feed 时的加载状态。
    @Published private(set) var isLoading = false

    // feed 加载失败时显示的错误文案。
    @Published private(set) var errorMessage: String?

    // 通过协议注入，方便测试或替换 feed 来源。
    private let feedService: YSWSFeedServicing

    init() {
        self.feedService = YSWSFeedService()
    }

    init(feedService: YSWSFeedServicing) {
        self.feedService = feedService
    }

    func loadIfNeeded() async {
        // 列表已经有数据时就不重复拉取，避免白白请求网络。
        guard projects.isEmpty else { return }
        await reload()
    }

    func reload() async {
        // 刷新开始时，先进入 loading 状态。
        isLoading = true
        errorMessage = nil

        do {
            // 拉取 RSS/Feed，然后过滤掉已经过期的项目。
            let feed = try await feedService.fetchFeed()
            let activeProjects = feed.items.filter { project in
                guard let daysLeft = project.daysLeft else { return true }
                return daysLeft >= 0
            }

            // 再按发布时间或截止日期排序，让最新内容排在前面。
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
            // 不把底层错误直接抛给 UI，只给一个统一提示。
            errorMessage = "Failed to load YSWS feed."
        }

        isLoading = false
    }
}
