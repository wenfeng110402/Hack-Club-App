import AuthenticationServices
import SwiftUI

struct OAuthView: View {
    @AppStorage("accessToken") private var accessToken = ""
    @AppStorage("isLoggedIn") private var isLoggedIn = false
    @State private var authSession: ASWebAuthenticationSession?
    @State private var isExchangingCode = false
    @State private var errorMessage: String?

    private let authService: HackClubAuthServicing = HackClubAuthService()
    private let clientID = "6dc569765a69d20c95f8f3ed84badce7"
    private let redirectURI = "hackclub-app://oauth"
    private let hackClubRed = Color(red: 236 / 255, green: 55 / 255, blue: 80 / 255)
    private let requestedScopes = "openid profile email verification_status slack_id"

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
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .frame(maxWidth: 320)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleSignIn() {
        HapticManager.impact(style: .soft, intensity: 0.8)
        let encodedScopes = requestedScopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? requestedScopes
        let authURL = URL(string: "https://auth.hackclub.com/oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(encodedScopes)")!

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
        isExchangingCode = true
        errorMessage = nil

        do {
            let token = try await authService.exchangeCodeForToken(code: code)
            accessToken = token.accessToken
            isLoggedIn = true
            HapticManager.notification(type: .success)
        } catch {
            errorMessage = "Token exchange failed."
            HapticManager.notification(type: .error)
        }

        isExchangingCode = false
    }
}
