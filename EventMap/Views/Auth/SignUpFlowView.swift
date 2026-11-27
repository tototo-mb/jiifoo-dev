import SwiftUI

// 新規登録の新しい流れ(形だけ。まだ Supabase にはつないでいない)
// ① メールアドレス → ② パスワードとユーザー名 → ③ 登録完了
// ※ 本番では ① と ② の間に「メールに届いた確認コードの入力」が入る予定
//    (つなぐときは「TODO: Supabase」と書いた所に処理を入れる)
// ※ 見た目の部品は AuthComponents.swift のものを使っている
struct SignUpFlowView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private enum Step: Int, CaseIterable {
        case email, profile, done

        var label: String {
            switch self {
            case .email:   return "メール"
            case .profile: return "パスワード・名前"
            case .done:    return "完了"
            }
        }
    }

    private enum Field { case email, password, passwordConfirm, userName }

    @State private var step: Step = .email
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""
    @State private var userName = ""
    @State private var agreed = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    private var theme: AuthTheme { AuthTheme(isDark: colorScheme == .dark) }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 20) {
                    stepIndicator
                    header
                    switch step {
                    case .email:   emailCard
                    case .profile: profileCard
                    case .done:    doneCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("新規登録")
        .navigationBarTitleDisplayMode(.inline)
        // ② では「戻る」で ① に戻る。③ では戻れない
        .navigationBarBackButtonHidden(step != .email)
        .toolbar {
            if step == .profile {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        go(to: .email)
                    } label: {
                        Label("戻る", systemImage: "chevron.left")
                    }
                }
            }
        }
        .tint(AuthTheme.primaryBlue)
        .keyboardCloseButton()
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: step)
    }

    // MARK: - 上の進み具合(① ② ③)
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                let isReached = item.rawValue <= step.rawValue
                VStack(spacing: 6) {
                    Capsule()
                        .fill(isReached ? AuthTheme.primaryBlue : theme.subText.opacity(0.25))
                        .frame(height: 5)
                    Text(item.label)
                        .font(.caption2.weight(item == step ? .bold : .regular))
                        .foregroundStyle(isReached ? theme.mainText : theme.subText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Step.allCases.count)段階中 \(step.rawValue + 1)段階目:\(step.label)")
    }

    // MARK: - 見出し
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
        .padding(.top, 4)
    }

    private var title: String {
        switch step {
        case .email:   return "メールアドレスを登録"
        case .profile: return "パスワードとユーザー名"
        case .done:    return "登録が完了しました"
        }
    }

    private var subtitle: String {
        switch step {
        case .email:   return "ログインに使うメールアドレスを入力してください"
        case .profile: return "ログインに使うパスワードと、アプリで表示される名前を決めてください"
        case .done:    return "jiifoo へようこそ！近くのイベントを探してみましょう"
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
                    .submitLabel(.next)
                    .onSubmit(submitEmail)
                    .focused($focusedField, equals: .email)
            }

            agreementRow

            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            AuthPrimaryButton(title: "次へ", isEnabled: !email.authTrimmed.isEmpty, action: submitEmail)
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

    // MARK: - ② パスワードとユーザー名
    private var profileCard: some View {
        AuthCard {
            // 登録するメールアドレスを確認用に出しておく
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .foregroundStyle(theme.subText)
                Text(email.authTrimmed)
                    .font(.footnote)
                    .foregroundStyle(theme.subText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }

            AuthField(icon: "lock.fill", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .password) {
                AuthPasswordInput(placeholder: "パスワード", text: $password, contentType: .newPassword)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .passwordConfirm }
                    .focused($focusedField, equals: .password)
            }

            AuthField(icon: "lock.rotation", iconColor: AuthTheme.skyBlue,
                      isFocused: focusedField == .passwordConfirm) {
                AuthPasswordInput(placeholder: "パスワード(確認用)", text: $passwordConfirm, contentType: .newPassword)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .userName }
                    .focused($focusedField, equals: .passwordConfirm)
            }

            Text("\(AuthRule.passwordMinLength)文字以上で、英字と数字を両方入れてください(記号も使えます)")
                .font(.caption)
                .foregroundStyle(theme.subText)
                .frame(maxWidth: .infinity, alignment: .leading)

            AuthField(icon: "face.smiling.fill", iconColor: AuthTheme.popOrange,
                      isFocused: focusedField == .userName) {
                TextField("ユーザー名(\(AuthRule.displayNameMaxLength)文字まで)", text: $userName)
                    .textContentType(.nickname)
                    .submitLabel(.done)
                    .onSubmit(submitProfile)
                    .focused($focusedField, equals: .userName)
            }

            if let errorMessage {
                AuthMessageBanner(message: errorMessage)
            }

            AuthPrimaryButton(title: "登録する", action: submitProfile)
                .padding(.top, 6)
        }
    }

    // MARK: - ③ 完了
    private var doneCard: some View {
        AuthCard {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(AuthTheme.primaryBlue)
                .symbolEffect(.bounce, value: step)
                .padding(.vertical, 8)

            Text("\(userName.authTrimmed) さん")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(theme.mainText)

            AuthPrimaryButton(title: "はじめる") {
                // TODO: Supabase につないだら、ログイン状態になって自動で地図の画面に切り替わる
                //       (今は形だけなので、ログイン画面に戻るだけ)
                dismiss()
            }
            .padding(.top, 6)
        }
    }

    // MARK: - 進む・戻る

    private func go(to newStep: Step) {
        errorMessage = nil
        focusedField = nil
        step = newStep
    }

    // ① → ②
    private func submitEmail() {
        guard AuthRule.looksLikeEmail(email.authTrimmed) else {
            errorMessage = "メールアドレスを正しく入力してください"
            return
        }
        guard agreed else {
            errorMessage = "利用規約とプライバシーポリシーへの同意が必要です"
            return
        }
        // TODO: Supabase … ここで確認コードを送り、コード入力の画面をはさむ
        go(to: .profile)
        focusedField = .password
    }

    // ② → ③
    private func submitProfile() {
        if let problem = AuthRule.passwordProblem(password) {
            errorMessage = problem
            return
        }
        if password != passwordConfirm {
            errorMessage = "確認用のパスワードが一致しません"
            return
        }
        let name = userName.authTrimmed
        if name.isEmpty {
            errorMessage = "ユーザー名を入力してください"
            return
        }
        if name.count > AuthRule.displayNameMaxLength {
            errorMessage = "ユーザー名は\(AuthRule.displayNameMaxLength)文字以内にしてください"
            return
        }
        // TODO: Supabase … ここでパスワードを設定し、プロフィールにユーザー名を保存する
        go(to: .done)
    }
}

#Preview {
    NavigationStack {
        SignUpFlowView()
    }
}
