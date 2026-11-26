import SwiftUI
 
struct LoginView: View {
    @Environment(\.colorScheme) private var colorScheme
 
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var isPasswordVisible = false
 
    @FocusState private var focusedField: Field?
 
    private enum Field {
        case email, password, displayName
    }
 
    // テーマカラー（青系パレット）
    private let primaryBlue = Color(red: 0.14, green: 0.45, blue: 0.95)
    private let skyBlue = Color(red: 0.35, green: 0.72, blue: 0.98)
    private let popOrange = Color(red: 1.00, green: 0.44, blue: 0.15)
 
    private var isDark: Bool { colorScheme == .dark }
 
    private var mainTextColor: Color {
        isDark ? .white : Color(red: 0.08, green: 0.18, blue: 0.35)
    }
 
    private var subTextColor: Color {
        isDark ? Color(red: 0.68, green: 0.76, blue: 0.88) : Color(red: 0.38, green: 0.49, blue: 0.64)
    }
 
    private var cardBackground: Color {
        isDark ? Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.96) : .white.opacity(0.96)
    }
 
    private var fieldIdleBackground: Color {
        isDark ? Color(red: 0.14, green: 0.20, blue: 0.31) : Color(red: 0.94, green: 0.97, blue: 1.00)
    }
 
    private var fieldFocusedBackground: Color {
        isDark ? Color(red: 0.16, green: 0.23, blue: 0.35) : .white
    }
 
    var body: some View {
        ZStack {
            backgroundLayer
 
            VStack(spacing: 28) {
                Spacer()
 
                // ロゴ（ライトモード / ダークモード切替・静止表示）
                // ※ Assets.xcassets に「jiifooLogoLight」「jiifooLogoDark」として登録してください
                //   （1つの Image Set で Any / Dark を設定した場合は Image("jiifooLogo") のみでOKです）
                Image(isDark ? "jiifooLogoDark" : "jiifooLogoLight")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 58)
 
                // 丸みのあるシンプル入力カード
                authCard
 
                // 下部モード切替リンク
                modeSwitchLink
 
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .tint(primaryBlue)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isSignUp)
        .onTapGesture {
            focusedField = nil
        }
        .keyboardCloseButton()
    }
 
    // MARK: - 背景
    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [
                        Color(red: 0.05, green: 0.08, blue: 0.14),
                        Color(red: 0.07, green: 0.11, blue: 0.19),
                        Color(red: 0.05, green: 0.09, blue: 0.16)
                    ]
                    : [
                        Color(red: 0.91, green: 0.96, blue: 1.00),
                        Color(red: 0.97, green: 0.99, blue: 1.00),
                        Color(red: 0.92, green: 0.96, blue: 1.00)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
 
            GeometryReader { geo in
                Circle()
                    .fill(skyBlue.opacity(isDark ? 0.12 : 0.18))
                    .frame(width: 240, height: 240)
                    .blur(radius: 30)
                    .offset(x: -70, y: -60)
 
                Circle()
                    .fill(primaryBlue.opacity(isDark ? 0.14 : 0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 32)
                    .offset(x: geo.size.width - 130, y: geo.size.height - 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
 
    // MARK: - 入力カード
    private var authCard: some View {
        VStack(spacing: 14) {
            // メールアドレス
            popTextField(
                icon: "envelope.fill",
                iconColor: primaryBlue,
                field: .email
            ) {
                TextField("メールアドレス", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
            }
 
            // パスワード
            popTextField(
                icon: "lock.fill",
                iconColor: skyBlue,
                field: .password
            ) {
                HStack(spacing: 8) {
                    Group {
                        if isPasswordVisible {
                            TextField("パスワード", text: $password)
                        } else {
                            SecureField("パスワード", text: $password)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(isSignUp ? .newPassword : .password)
 
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.subheadline)
                            .foregroundStyle(subTextColor.opacity(0.75))
                    }
                }
            }
 
            // 表示名（新規登録時のみ表示）
            if isSignUp {
                popTextField(
                    icon: "face.smiling.fill",
                    iconColor: popOrange,
                    field: .displayName
                ) {
                    TextField("表示名", text: $displayName)
                        .textContentType(.nickname)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
 
            // エラーメッセージ
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.red.opacity(isDark ? 0.16 : 0.08))
                )
            }
 
            // 送信ボタン
            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(isSignUp ? "新規登録" : "ログイン")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [primaryBlue, skyBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .shadow(color: primaryBlue.opacity(isDark ? 0.35 : 0.26), radius: 10, y: 5)
            }
            .buttonStyle(PopPressButtonStyle())
            .disabled(isBusy)
            .opacity(isBusy ? 0.65 : 1.0)
            .padding(.top, 6)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    isDark ? skyBlue.opacity(0.20) : primaryBlue.opacity(0.12),
                    lineWidth: 1.2
                )
        )
        .shadow(color: isDark ? .black.opacity(0.35) : primaryBlue.opacity(0.08), radius: 20, y: 8)
    }
 
    // MARK: - 丸みのある入力フィールド共通パーツ
    private func popTextField<Content: View>(
        icon: String,
        iconColor: Color,
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = (focusedField == field)
 
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(isFocused ? 0.22 : 0.14))
                    .frame(width: 34, height: 34)
 
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
 
            content()
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(mainTextColor)
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(isFocused ? fieldFocusedBackground : fieldIdleBackground)
        )
        .overlay(
            Capsule()
                .stroke(
                    isFocused ? iconColor.opacity(0.75) : primaryBlue.opacity(isDark ? 0.16 : 0.08),
                    lineWidth: isFocused ? 1.6 : 1
                )
        )
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
 
    // MARK: - 下部切り替えリンク
    private var modeSwitchLink: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                isSignUp.toggle()
                errorMessage = nil
            }
        } label: {
            HStack(spacing: 4) {
                Text(isSignUp ? "すでにアカウントをお持ちの方は" : "はじめての方は")
                    .foregroundStyle(subTextColor)
                Text(isSignUp ? "ログイン" : "新規登録")
                    .fontWeight(.bold)
                    .foregroundStyle(isDark ? skyBlue : primaryBlue)
            }
            .font(.system(size: 13.5, weight: .medium, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .disabled(isBusy)
    }
 
    // MARK: - 送信処理
    private func submit() {
        focusedField = nil
        Task {
            isBusy = true
            errorMessage = nil
            do {
                if isSignUp {
                    try await JiifooAPI.signUp(email: email, password: password, displayName: displayName)
                } else {
                    try await JiifooAPI.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = "入力内容に誤りがあります。内容を確認してください"
            }
            isBusy = false
        }
    }
}
 
// MARK: - 押し心地のあるボタンスタイル
private struct PopPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}
 
 
