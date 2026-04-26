import AuthenticationServices
import SwiftUI

// MARK: - OAuth 登录页
struct OAuthView: View {
    // 登录成功后保存 token 和登录态，供整个 App 使用。
    @AppStorage("accessToken") private var accessToken = ""
    @AppStorage("isLoggedIn") private var isLoggedIn = false

    // ASWebAuthenticationSession 用来打开系统授权页并接收回调。
    @State private var authSession: ASWebAuthenticationSession?

    // 这个状态用于显示“正在换 token”的加载状态。
    @State private var isExchangingCode = false

    // 出错时在页面上展示给用户看。
    @State private var errorMessage: String?

    // 登录相关配置。
    private let authService: HackClubAuthServicing = HackClubAuthService()
    private let clientID = "6dc569765a69d20c95f8f3ed84badce7"
    private let redirectURI = "hackclub-app://oauth"
    private let hackClubRed = Color(red: 236 / 255, green: 55 / 255, blue: 80 / 255)
    private let requestedScopes = "openid profile email name verification_status slack_id"

    var body: some View {
        ZStack {
            AppPalette.background.ignoresSafeArea()
            AppPalette.backgroundGlow.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 24) {
                    Image("flag-standalone")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 64)

                    Text("Welcome to\n\(Text("Hack Club.").foregroundColor(hackClubRed))")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .lineSpacing(-5)
                        .foregroundColor(.white)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppPalette.danger)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 40)

                VStack(spacing: 20) {
                    Button(action: handleSignIn) {
                        HStack(spacing: 12) {
                            if isExchangingCode {
                                ProgressView()
                                    .tint(.white)
                                    .frame(width: 28, height: 28)
                            } else {
                                Image("icon-rounded")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                            }

                            Text(isExchangingCode ? "Signing in..." : "Log in with HCA")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .modifier(GlassCardModifier(emphasis: .neutral))
                    }
                    .disabled(isExchangingCode)
                    .buttonStyle(.plain)

                    Button {
                        HapticManager.impact(style: .soft, intensity: 0.8)
                        withAnimation {
                            accessToken = ""
                            isLoggedIn = true
                        }
                    } label: {
                        Text("Continue as Guest")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }
                    .disabled(isExchangingCode)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleSignIn() {
        // 触发一次轻量震动，让用户知道按钮被按下了。
        HapticManager.impact(style: .soft, intensity: 0.8)

        // 拼出授权 URL，系统会把用户带到 Hack Club 的登录/授权页。
        let encodedScopes = requestedScopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? requestedScopes
        let authURL = URL(string: "https://auth.hackclub.com/oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(encodedScopes)")!

        // 授权完成后，系统会把 callback URL 回传给我们。
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "hackclub-app") { callbackURL, error in
            if let error {
                HapticManager.notification(type: .error)
                errorMessage = error.localizedDescription
                return
            }

            guard
                let callbackURL,
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                let code = components.queryItems?.first(where: { $0.name == "code" })?.value
            else {
                errorMessage = "Missing authorization code."
                return
            }

            // 拿到 code 以后，再去和后端交换 access token。
            Task {
                await exchange(code: code)
            }
        }

        session.presentationContextProvider = AuthPresentationContext.shared
        authSession = session
        session.start()
    }

    @MainActor
    private func exchange(code: String) async {
        // 开始换 token 时显示 loading，避免用户重复点击。
        isExchangingCode = true
        errorMessage = nil

        do {
            // 用授权码换 token，成功后就可以进入主页面了。
            let token = try await authService.exchangeCodeForToken(code: code)
            accessToken = token.accessToken
            isLoggedIn = true
            HapticManager.notification(type: .success)
        } catch {
            // 失败时把错误展示出来，便于排查登录问题。
            errorMessage = "Token exchange failed: \(error.localizedDescription)"
            print("Token exchange error: \(error)")
            HapticManager.notification(type: .error)
        }

        isExchangingCode = false
    }
}

#Preview {
    OAuthView()
}
