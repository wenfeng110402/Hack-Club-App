import SwiftUI
import UIKit

// MARK: - App 主入口壳
struct ContentView: View {
    @AppStorage("accessToken") private var accessToken = ""
    @StateObject private var session = SessionViewModel()
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(session: session)
                .tag(AppTab.home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            YSWSView()
                .tag(AppTab.ysws)
                .tabItem {
                    Label("YSWS", systemImage: "square.stack.3d.up.fill")
                }

            SettingsView(session: session)
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .task(id: accessToken) {
            await session.refreshUser(accessToken: accessToken)
        }
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
        }
        .onAppear(perform: configureTabBar)
        .preferredColorScheme(.dark)
    }

    private func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1)
        appearance.shadowColor = UIColor.clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

private enum AppTab {
    case home
    case ysws
    case settings
}

// MARK: - 首页
struct HomeView: View {
    @ObservedObject var session: SessionViewModel
    @State private var previousVerificationState = false
    @State private var toastMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.background.ignoresSafeArea()
                AppPalette.backgroundGlow.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroCard
                        profileGrid
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
            .overlay(alignment: .top) {
                if let toastMessage {
                    ToastBanner(message: toastMessage)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle("Home")
            .onAppear {
                previousVerificationState = session.user?.isVerifiedMember ?? false
            }
            .onChange(of: session.user?.isVerifiedMember ?? false) { _, isVerified in
                guard isVerified != previousVerificationState else { return }
                if isVerified {
                    HapticManager.notification(type: .success)
                } else {
                    HapticManager.impact(style: .rigid, intensity: 0.55)
                }
                previousVerificationState = isVerified
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.user?.displayName ?? "Hack Clubber")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    HStack(spacing: 10) {
                        Image(systemName: session.user?.isVerifiedMember == true ? "checkmark.seal.fill" : "xmark.shield.fill")
                            .foregroundStyle(session.user?.isVerifiedMember == true ? AppPalette.success : AppPalette.danger)

                        Text(session.user?.statusTitle ?? "Not Verified")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.84))
                    }

                    Text(session.user?.statusSummary ?? "Connect with Hack Club Auth to populate your profile.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Signals")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))

                    Text("\(session.user?.verificationSignals.count ?? 0)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppPalette.danger)
            }

            if session.isLoading {
                ProgressView()
                    .tint(.white.opacity(0.8))
            }
        }
        .padding(24)
        .modifier(GlassCardModifier(emphasis: session.user?.isVerifiedMember == true ? .success : .neutral))
    }

    private var profileGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(session.user?.profileRows ?? placeholderRows) { item in
                // 如果是 Hackatime 卡片，用 NavigationLink 包裹
                if item.title == "Hackatime" {
                    NavigationLink {
                        HackatimeView()
                    } label: {
                        ProfileInfoCard(item: item) { _ in
                            showCopyToast()
                        }
                    }
                    .buttonStyle(.plain) // 保持卡片原有样式，不被系统按钮变灰
                } else {
                    ProfileInfoCard(item: item) { _ in
                        showCopyToast()
                    }
                }
            }
        }
    }

    private var placeholderRows: [ProfileCardItem] {
        [
            ProfileCardItem(title: "YSWS Eligible", value: "Waiting for login", detail: "Authorize with Hack Club Auth", systemImage: "checkmark.seal.fill", tintHex: 0x2EA043),
            ProfileCardItem(title: "Hackatime", value: "Unavailable", detail: "Currently unavailable", systemImage: "timer", tintHex: 0x58A6FF),
            ProfileCardItem(title: "Slack ID", value: "Unavailable", detail: "Request `slack_id` scope if needed", systemImage: "number.square.fill", tintHex: 0xDB61A2),
            ProfileCardItem(title: "Identity ID", value: "Unavailable", detail: "Returned by `openid`", systemImage: "person.text.rectangle.fill", tintHex: 0x8B949E),
            ProfileCardItem(title: "Mail", value: "will come", detail: "will come", systemImage: "envelope.fill", tintHex: 0xD29922)
        ]
    }

    private func showCopyToast() {
        // 复制成功后给一个很短的 toast。
        // 这里不用 alert，因为 alert 会打断当前操作。
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            toastMessage = "Copied!"
        }

        HapticManager.selection()

        // 一小段时间后自动隐藏 toast。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.easeOut(duration: 0.2)) {
                toastMessage = nil
            }
        }
    }
}

// MARK: - 可复用的小卡片
struct ProfileInfoCard: View {
    let item: ProfileCardItem
    let onCopy: (String) -> Void

    init(item: ProfileCardItem, onCopy: @escaping (String) -> Void = { _ in }) {
        self.item = item
        self.onCopy = onCopy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: item.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: item.tintHex))
                
                // 针对可点击的卡片加一个向右的箭头，代表这是一个入口
                if item.title == "Hackatime" {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, 4)
                }
                
                Spacer()
            }

            Spacer(minLength: 4)

            Text(item.title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.42))

            Text(item.value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .contentShape(Rectangle())
                .modifier(CopyableTextModifier(copyValue: item.copyValue, onCopy: onCopy))
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .padding(18)
        .modifier(GlassCardModifier(emphasis: .neutral))
    }
}

private struct CopyableTextModifier: ViewModifier {
    let copyValue: String?
    let onCopy: (String) -> Void

    func body(content: Content) -> some View {
        content
            // 这里只让文字本身响应长按，避免整张卡片和其他手势冲突。
            .accessibilityHint(copyValue == nil ? "No copy action available" : "Long press to copy")
            .onLongPressGesture(minimumDuration: 0.35) {
                copyText()
            }
    }

    private func copyText() {
        // 只有存在可复制内容时，才写入剪贴板。
        guard let copyValue, !copyValue.isEmpty else { return }
        UIPasteboard.general.string = copyValue
        HapticManager.selection()
        // 把“已复制”的事件交回给 HomeView 去显示 toast。
        onCopy(copyValue)
    }
}

private struct ToastBanner: View {
    let message: String

    var body: some View {
        // 一个很轻量的顶部提示条，不会明显打断用户操作。
        Text(message)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
    }
}

// MARK: - YSWS 列表页
struct YSWSView: View {
    @StateObject private var viewModel = YSWSDashboardViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.background.ignoresSafeArea()

                Group {
                    if viewModel.isLoading && viewModel.projects.isEmpty {
                        ProgressView()
                            .tint(.white)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.projects.isEmpty {
                        ContentUnavailableView("YSWS Unavailable", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                            .foregroundStyle(.white.opacity(0.8))
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(viewModel.projects) { project in
                                    YSWSProjectCard(project: project)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .navigationTitle("YSWS")
            .task {
                await viewModel.loadIfNeeded()
            }
            .refreshable {
                HapticManager.selection()
                await viewModel.reload()
                if viewModel.errorMessage == nil {
                    HapticManager.impact(style: .soft, intensity: 0.65)
                } else {
                    HapticManager.notification(type: .warning)
                }
            }
        }
    }
}

struct YSWSProjectCard: View {
    let project: YSWSProject

    var body: some View {
        Link(destination: project.link ?? URL(string: "https://ysws.hackclub.com")!) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(project.title)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(project.summary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(3)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.34))
                }

                Divider()
                    .overlay(.white.opacity(0.08))

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("DEADLINE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.42))

                        Text(project.deadlineLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))

                        if let slackChannel = project.slackChannel {
                            Text("#\(slackChannel)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppPalette.accent)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("DAYS LEFT")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.42))

                        Text(project.daysLeft.map(String.init) ?? "∞")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(project.relativeSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(20)
            .modifier(GlassCardModifier(emphasis: .neutral))
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                HapticManager.impact(style: .soft, intensity: 0.7)
            }
        )
        .buttonStyle(.plain)
    }
}

// MARK: - 设置页
struct SettingsView: View {
    @AppStorage("accessToken") private var accessToken = ""
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @ObservedObject var session: SessionViewModel
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.user?.displayName ?? "Hack Clubber")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text(session.user?.email ?? "Connected via Hack Club Auth")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    NavigationLink {
                        InfoView()
                    } label: {
                        Label("Info", systemImage: "info.circle")
                    }

                    Button(role: .destructive) {
                        HapticManager.selection()
                        showLogoutConfirm = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppPalette.background.ignoresSafeArea())
            .listRowBackground(AppPalette.cardBackground)
            .navigationTitle("Settings")
            .confirmationDialog("Are you sure?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Log Out", role: .destructive, action: handleLogout)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func handleLogout() {
        HapticManager.notification(type: .warning)
        accessToken = ""
        isLoggedIn = false
        session.clear()
    }
}

// MARK: - 卡片统一样式
enum CardEmphasis {
    case neutral
    case success
}

struct GlassCardModifier: ViewModifier {
    let emphasis: CardEmphasis

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppPalette.cardBackground)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.18))
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(strokeGradient, lineWidth: 1)
                    .blendMode(.overlay)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(AppPalette.edgeGlow.opacity(0.32), lineWidth: 0.75)
                    .blur(radius: 0.8)
                    .blendMode(.plusDarker)
            }
            .shadow(color: Color.black.opacity(0.34), radius: 24, x: 0, y: 18)
            .shadow(color: shadowTint.opacity(0.16), radius: 10, x: 0, y: 1)
    }

    private var strokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.12),
                shadowTint.opacity(0.16),
                Color.white.opacity(0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var shadowTint: Color {
        switch emphasis {
        case .neutral:
            return AppPalette.edgeGlow
        case .success:
            return AppPalette.success
        }
    }
}

// MARK: - 设计色板
enum AppPalette {
    static let background = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let cardBackground = Color(red: 0.10, green: 0.11, blue: 0.13).opacity(0.9)
    static let edgeGlow = Color(red: 0.36, green: 0.38, blue: 0.42)
    static let accent = Color(hex: 0x58A6FF)
    static let success = Color(hex: 0x2EA043)
    static let danger = Color(hex: 0xF85149)

    static let backgroundGlow = LinearGradient(
        colors: [
            Color.white.opacity(0.02),
            Color.clear,
            Color(hex: 0x58A6FF).opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 颜色工具
extension Color {
    init(hex: Int) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    ContentView()
}
