import SwiftUI

// 新規登録
// ① メールアドレス・パスワード・表示名を入力して「確認コードを送る」
// ② メールに届いた確認コードを入力して「登録する」
//    → 確認できるとログイン状態になり、自動で地図の画面に切り替わる
// ※ Supabase の「Confirm email」をオンにし、メールの文面に {{ .Token }}(確認コード)を入れておくこと
struct SignUpView: View {
    @Environment(\.colorScheme) private var colorScheme

    private enum Step { case form, code }
    private enum Field { case email, password, passwordConfirm, displayName, code }

    @State private var step: Step
    @State private var email: String
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var displayName = ""
    @State private var agreed = false
    @State private var code = ""

    @State private var errorMessage: String?
    @State private var noticeMessage: String?
    @State private var isBusy = false
    @State private var resendWait = 0              // 確認コードを送り直せるまでの秒数
    @State private var cooldownID = 0              // 送り直しの待ち時間を数え始めた合図

    @FocusState private var focusedField: Field?

    // ログイン画面の「確認コードを入力する」から来たとき:コードを送り直して、入力から始める
    private let resendOnAppear: Bool
    @State private var didResendOnAppear = false

    init() {
        _step = State(initialValue: .form)
        _email = State(initialValue: "")
        resendOnAppear = false
    }

    init(confirmingEmail: String) {
        _step = State(initialValue: .code)
        _email = State(initialValue: confirmingEmail)
        resendOnAppear = true
    }

    private var theme: AuthTheme { AuthTheme(isDark: colorScheme == .dark) }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    switch step {
                    case .form: formCard
                    case .code: codeCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("新規登録")
        .navigationBarTitleDisplayMode(.inline)
        .tint(AuthTheme.primaryBlue)
        .keyboardCloseButton()
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: step)
        .task(id: cooldownID) {
            // 送り直しボタンの待ち時間を1秒ずつ減らす
            while resendWait > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendWait -= 1
            }
        }
        .onAppear {
            if resendOnAppear && !didResendOnAppear {
                didResendOnAppear = true
                resend()
            }
        }
    }

    // MARK: - 上の説明
    private var header: some View {
        VStack(spacing: 6) {
            Text(step == .form ? "アカウントを作成" : "メールを確認")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(theme.mainText)
            Text(step == .form
                 ? "入力したメールアドレスに確認コードを送ります"
                 : "\(email) に届いた確認コードを入力してください")
                .font(.footnote)
                .foregroundStyle(theme.subText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - ① 入力
    private var formCard: some View {
        AuthCard {
            AuthField(icon: "envelope.fill", iconColor: AuthTheme.primaryBlue,
                      isFocused: focusedField == .email) {
                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .focused($focusedField, equals: .email)
            }

            AuthField(icon: "lock.fill", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .password) {
                // .newPassword にすると、iPhone が強いパスワードを提案してくれる
                AuthPasswordInput(placeholder: "パスワード", text: $password, contentType: .newPassword)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .passwordConfirm }
                    .focused($focusedField, equals: .password)
            }

            AuthField(icon: "lock.rotation", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .passwordConfirm) {
                AuthPasswordInput(placeholder: "パスワード(確認用)", text: $passwordConfirm, contentType: .newPassword)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .displayName }
                    .focused($focusedField, equals: .passwordConfirm)
            }

            Text("\(AuthRule.passwordMinLength)文字以上で、英字と数字を両方入れてください")
                .font(.caption)
                .foregroundStyle(theme.subText)
                .frame(maxWidth: .infinity, alignment: .leading)

            AuthField(icon: "face.smiling.fill", iconColor: AuthTheme.popOrange,
                      isFocused: focusedField == .displayName) {
                TextField("表示名(\(AuthRule.displayNameMaxLength)文字まで)", text: $displayName)
                    .textContentType(.nickname)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .displayName)
            }

            agreementRow

            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            AuthPrimaryButton(title: "確認コードを送る", isBusy: isBusy, action: signUp)
                .padding(.top, 6)
        }
    }

    // 利用規約・プライバシーポリシーへの同意
    // TODO: 規約のページができたら、文字をリンクにする
    private var agreementRow: some View {
        Button {
            agreed.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: agreed ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(agreed ? AuthTheme.primaryBlue : theme.subText)
                Text("利用規約とプライバシーポリシーに同意する")
                    .font(.footnote)
                    .foregroundStyle(theme.mainText)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(agreed ? .isSelected : [])
    }

    // 入力に問題があれば、その説明(なければ nil)
    private var formProblem: String? {
        if !AuthRule.looksLikeEmail(email.authTrimmed) {
            return "メールアドレスを正しく入力してください"
        }
        if let problem = AuthRule.passwordProblem(password) {
            return problem
        }
        if password != passwordConfirm {
            return "確認用のパスワードが一致しません"
        }
        let name = displayName.authTrimmed
        if name.isEmpty {
            return "表示名を入力してください"
        }
        if name.count > AuthRule.displayNameMaxLength {
            return "表示名は\(AuthRule.displayNameMaxLength)文字以内にしてください"
        }
        if !agreed {
            return "利用規約とプライバシーポリシーへの同意が必要です"
        }
        return nil
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

            AuthPrimaryButton(title: "登録する", isBusy: isBusy, isEnabled: code.count >= 6, action: verify)
                .padding(.top, 6)

            HStack {
                AuthTextButton(title: resendWait > 0 ? "コードを再送(\(resendWait)秒)" : "コードを再送") {
                    resend()
                }
                .disabled(resendWait > 0 || isBusy)

                Spacer()

                // 最初から入力してきたときだけ、メールアドレスを直せるようにする
                if !resendOnAppear {
                    AuthTextButton(title: "メールアドレスを直す") {
                        errorMessage = nil
                        noticeMessage = nil
                        code = ""
                        step = .form
                    }
                }
            }

            Text("届かないときは、迷惑メールのフォルダも確認してください")
                .font(.caption)
                .foregroundStyle(theme.subText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 処理

    // ① 登録して、確認コードを送ってもらう
    private func signUp() {
        if let problem = formProblem {
            errorMessage = problem
            return
        }
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            do {
                let needsConfirm = try await JiifooAPI.signUp(
                    email: email.authTrimmed,
                    password: password,
                    displayName: displayName.authTrimmed)
                // Supabase で「Confirm email」がオフだと、ここでそのままログインになる(画面は自動で切り替わる)
                if needsConfirm {
                    code = ""
                    noticeMessage = "\(email.authTrimmed) に確認コードを送りました"
                    startCooldown()
                    step = .code
                    focusedField = .code
                }
            } catch {
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "登録できませんでした。通信状況を確認して、もう一度お試しください")
            }
            isBusy = false
        }
    }

    // ② 確認コードを確かめる(成功するとログイン状態になり、地図の画面に切り替わる)
    private func verify() {
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            do {
                try await JiifooAPI.verifySignUpCode(email: email.authTrimmed, code: code)
            } catch {
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "確認できませんでした。コードを確認して、もう一度お試しください")
            }
            isBusy = false
        }
    }

    // 確認コードを送り直す
    private func resend() {
        Task {
            errorMessage = nil
            do {
                try await JiifooAPI.resendSignUpCode(email: email.authTrimmed)
                noticeMessage = "\(email.authTrimmed) に確認コードを送りました"
                startCooldown()
            } catch {
                errorMessage = AuthErrorText.message(
                    for: error,
                    fallback: "確認コードを送れませんでした。少し待ってからもう一度お試しください")
            }
        }
    }

    // 送り直しは60秒あける(Supabase も同じ人へのメールは60秒に1回まで)
    private func startCooldown() {
        resendWait = 60
        cooldownID += 1
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
}
