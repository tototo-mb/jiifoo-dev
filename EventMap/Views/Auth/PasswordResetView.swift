import SwiftUI

// パスワード再設定
// ① メールアドレスを入力して「確認コードを送る」
// ② メールに届いた確認コードを入力
// ③ 新しいパスワードを決める → 地図の画面へ
// ※ ② で確認できた時点でログイン状態になるが、③ が終わるまでは地図に進まないよう
//    AuthManager.isResettingPassword で止めている(EventMapApp.swift)
// ※ Supabase の「Reset Password」のメールの文面に {{ .Token }}(確認コード)を入れておくこと
struct PasswordResetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AuthManager.self) private var authManager

    private enum Step { case email, code, newPassword }
    private enum Field { case email, code, password, passwordConfirm }

    @State private var step: Step = .email
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var passwordConfirm = ""

    @State private var errorMessage: String?
    @State private var noticeMessage: String?
    @State private var isBusy = false
    @State private var resendWait = 0
    @State private var cooldownID = 0

    @FocusState private var focusedField: Field?

    init(initialEmail: String = "") {
        _email = State(initialValue: initialEmail)
    }

    private var theme: AuthTheme { AuthTheme(isDark: colorScheme == .dark) }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    switch step {
                    case .email:       emailCard
                    case .code:        codeCard
                    case .newPassword: newPasswordCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("パスワードの再設定")
        .navigationBarTitleDisplayMode(.inline)
        // 新しいパスワードを決める段階では戻れないようにする(ログイン状態のまま中途半端にならないように)
        .navigationBarBackButtonHidden(step == .newPassword)
        .tint(AuthTheme.primaryBlue)
        .keyboardCloseButton()
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: step)
        .task(id: cooldownID) {
            while resendWait > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendWait -= 1
            }
        }
    }

    // MARK: - 上の説明
    private var header: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.mainText)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(theme.subText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var title: String {
        switch step {
        case .email:       return "パスワードを忘れた方"
        case .code:        return "メールを確認"
        case .newPassword: return "新しいパスワード"
        }
    }

    private var subtitle: String {
        switch step {
        case .email:       return "登録したメールアドレスに確認コードを送ります"
        case .code:        return "\(email.authTrimmed) に届いた確認コードを入力してください"
        case .newPassword: return "新しいパスワードを決めてください"
        }
    }

    // MARK: - ① メールアドレス
    private var emailCard: some View {
        AuthCard {
            AuthField(icon: "envelope.fill", iconColor: AuthTheme.primaryBlue,
                      isFocused: focusedField == .email) {
                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .submitLabel(.send)
                    .onSubmit(sendCode)
                    .focused($focusedField, equals: .email)
            }

            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            AuthPrimaryButton(title: "確認コードを送る", isBusy: isBusy,
                              isEnabled: !email.authTrimmed.isEmpty, action: sendCode)
                .padding(.top, 6)
        }
    }

    // MARK: - ② 確認コード
    private var codeCard: some View {
        AuthCard {
            if let noticeMessage {
                AuthMessageBanner(message: noticeMessage, isError: false)
            }

            AuthField(icon: "number", iconColor: AuthTheme.primaryBlue,
                      isFocused: focusedField == .code) {
                AuthCodeInput(code: $code)
                    .focused($focusedField, equals: .code)
            }

            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            AuthPrimaryButton(title: "次へ", isBusy: isBusy, isEnabled: code.count >= 6, action: verify)
                .padding(.top, 6)

            HStack {
                AuthTextButton(title: resendWait > 0 ? "コードを再送(\(resendWait)秒)" : "コードを再送") {
                    sendCode()
                }
                .disabled(resendWait > 0 || isBusy)

                Spacer()

                AuthTextButton(title: "メールアドレスを直す") {
                    errorMessage = nil
                    noticeMessage = nil
                    code = ""
                    step = .email
                }
            }

            Text("届かないときは、迷惑メールのフォルダも確認してください")
                .font(.caption)
                .foregroundStyle(theme.subText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - ③ 新しいパスワード
    private var newPasswordCard: some View {
        AuthCard {
            AuthField(icon: "lock.fill", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .password) {
                AuthPasswordInput(placeholder: "新しいパスワード", text: $password, contentType: .newPassword)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .passwordConfirm }
                    .focused($focusedField, equals: .password)
            }

            AuthField(icon: "lock.rotation", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .passwordConfirm) {
                AuthPasswordInput(placeholder: "新しいパスワード(確認用)", text: $passwordConfirm,
                                  contentType: .newPassword)
                    .submitLabel(.done)
                    .onSubmit(updatePassword)
                    .focused($focusedField, equals: .passwordConfirm)
            }

            Text("\(AuthRule.passwordMinLength)文字以上で、英字と数字を両方入れてください")
                .font(.caption)
                .foregroundStyle(theme.subText)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            AuthPrimaryButton(title: "パスワードを変更する", isBusy: isBusy, action: updatePassword)
                .padding(.top, 6)
        }
    }

    // MARK: - 処理

    // ① 確認コードを送る
    // ※ 登録されていないメールアドレスでも、Supabase はエラーを返さない(登録の有無を知られないため)
    private func sendCode() {
        guard AuthRule.looksLikeEmail(email.authTrimmed) else {
            errorMessage = "メールアドレスを正しく入力してください"
            return
        }
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            do {
                try await JiifooAPI.sendPasswordResetCode(email: email.authTrimmed)
                noticeMessage = "登録されているメールアドレスなら、確認コードが届きます"
                code = ""
                resendWait = 60
                cooldownID += 1
                step = .code
                focusedField = .code
            } catch {
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "確認コードを送れませんでした。少し待ってからもう一度お試しください")
            }
            isBusy = false
        }
    }

    // ② 確認コードを確かめる(成功するとログイン状態になるが、地図にはまだ進まない)
    private func verify() {
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            authManager.isResettingPassword = true   // 先に止めておく(確認できた瞬間に地図へ切り替わらないように)
            do {
                try await JiifooAPI.verifyPasswordResetCode(email: email.authTrimmed, code: code)
                step = .newPassword
                focusedField = .password
            } catch {
                authManager.isResettingPassword = false
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "確認できませんでした。コードを確認して、もう一度お試しください")
            }
            isBusy = false
        }
    }

    // ③ 新しいパスワードにする → 地図の画面へ
    private func updatePassword() {
        if let problem = AuthRule.passwordProblem(password) {
            errorMessage = problem
            return
        }
        if password != passwordConfirm {
            errorMessage = "確認用のパスワードが一致しません"
            return
        }
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            do {
                try await JiifooAPI.updatePassword(password)
                authManager.isResettingPassword = false   // これで地図の画面に切り替わる
            } catch {
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "パスワードを変更できませんでした。もう一度お試しください")
            }
            isBusy = false
        }
    }
}

#Preview {
    NavigationStack {
        PasswordResetView()
            .environment(AuthManager())
    }
}
