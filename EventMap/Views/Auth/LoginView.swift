import SwiftUI

// ログイン画面
// ・ログインだけを置き、新規登録とパスワード再設定は下のボタンから別の画面へ進む
// ・見た目の部品は AuthComponents.swift にまとめてある
struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var needsEmailConfirm = false   // メールの確認が終わっていないアカウントだった
    @State private var path: [AuthRoute] = []

    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var isDark: Bool { colorScheme == .dark }
    private var theme: AuthTheme { AuthTheme(isDark: isDark) }
    private var canSubmit: Bool { !email.authTrimmed.isEmpty && !password.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AuthBackground()

                VStack(spacing: 28) {
                    Spacer()

                    // ロゴ（ライトモード / ダークモード切替）
                    Image(isDark ? "jiifooLogoDark" : "jiifooLogoLight")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 58)

                    loginCard

                    signUpLink

                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .tint(AuthTheme.primaryBlue)
            .onTapGesture { focusedField = nil }
            .keyboardCloseButton()
            .navigationDestination(for: AuthRoute.self) { route in
                switch route {
                case .signUp:
                    SignUpFlowView()
                case .confirmEmail(let email):
                    SignUpView(confirmingEmail: email)
                case .passwordReset(let email):
                    PasswordResetView(initialEmail: email)
                }
            }
        }
    }

    // MARK: - 入力カード
    private var loginCard: some View {
        AuthCard {
            // メールアドレス
            AuthField(icon: "envelope.fill", iconColor: AuthTheme.primaryBlue,
                      isFocused: focusedField == .email) {
                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)   // パスワードの自動入力(キーチェーン)と組み合わせるため
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .focused($focusedField, equals: .email)
            }

            // パスワード
            AuthField(icon: "lock.fill", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .password) {
                AuthPasswordInput(placeholder: "パスワード", text: $password, contentType: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .focused($focusedField, equals: .password)
            }

            // パスワードを忘れた方
            AuthTextButton(title: "パスワードを忘れた方") {
                path.append(.passwordReset(email: email.authTrimmed))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // エラー
            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            // メールの確認が終わっていなかったとき:確認コードの入力へ
            if needsEmailConfirm {
                AuthTextButton(title: "確認コードを入力する") {
                    path.append(.confirmEmail(email: email.authTrimmed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            AuthPrimaryButton(title: "ログイン", isBusy: isBusy, isEnabled: canSubmit, action: submit)
                .padding(.top, 6)
        }
    }

    // MARK: - 下の「新規登録」
    private var signUpLink: some View {
        Button {
            errorMessage = nil
            path.append(.signUp)
        } label: {
            HStack(spacing: 4) {
                Text("アカウントをお持ちでない方は")
                    .foregroundStyle(theme.subText)
                Text("新規登録")
                    .fontWeight(.bold)
                    .foregroundStyle(isDark ? AuthTheme.skyBlue : AuthTheme.primaryBlue)
            }
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .disabled(isBusy)
    }

    // MARK: - ログイン
    private func submit() {
        guard canSubmit, !isBusy else { return }
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            needsEmailConfirm = false
            do {
                // 成功すると AuthManager がログインに気づいて、地図の画面に切り替わる
                try await JiifooAPI.signIn(email: email.authTrimmed, password: password)
            } catch {
                let code = AuthErrorText.code(of: error)
                needsEmailConfirm = code == "email_not_confirmed"
                // メールアドレスかパスワードが違うときは、パスワードを消して入力し直してもらう
                // (通信エラーのときは、もう一度押すだけで済むように残しておく)
                if code == "invalid_credentials" {
                    password = ""
                    focusedField = .password
                }
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "ログインできませんでした。通信状況を確認して、もう一度お試しください")
            }
            isBusy = false
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}
