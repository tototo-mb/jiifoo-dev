import SwiftUI
import Supabase

// ログイン・新規登録・パスワード再設定で共通の見た目と部品
// (元は LoginView の中にあったデザインを、ほかの画面でも使えるように取り出したもの)

// MARK: - 画面の行き先

enum AuthRoute: Hashable {
    case signUp                          // 新規登録
    case confirmEmail(email: String)     // 確認が終わっていないアカウントの確認コード入力
    case passwordReset(email: String)    // パスワード再設定
}

// MARK: - 色

struct AuthTheme {
    let isDark: Bool

    static let primaryBlue = Color(red: 0.14, green: 0.45, blue: 0.95)
    static let skyBlue = Color(red: 0.35, green: 0.72, blue: 0.98)
    static let popOrange = Color(red: 1.00, green: 0.44, blue: 0.15)

    var mainText: Color {
        isDark ? .white : Color(red: 0.08, green: 0.18, blue: 0.35)
    }
    var subText: Color {
        isDark ? Color(red: 0.68, green: 0.76, blue: 0.88) : Color(red: 0.38, green: 0.49, blue: 0.64)
    }
    var cardBackground: Color {
        isDark ? Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.96) : .white.opacity(0.96)
    }
    var fieldIdle: Color {
        isDark ? Color(red: 0.14, green: 0.20, blue: 0.31) : Color(red: 0.94, green: 0.97, blue: 1.00)
    }
    var fieldFocused: Color {
        isDark ? Color(red: 0.16, green: 0.23, blue: 0.35) : .white
    }
}

// MARK: - 背景

struct AuthBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: isDark
                    ? [Color(red: 0.05, green: 0.08, blue: 0.14),
                       Color(red: 0.07, green: 0.11, blue: 0.19),
                       Color(red: 0.05, green: 0.09, blue: 0.16)]
                    : [Color(red: 0.91, green: 0.96, blue: 1.00),
                       Color(red: 0.97, green: 0.99, blue: 1.00),
                       Color(red: 0.92, green: 0.96, blue: 1.00)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { geo in
                Circle()
                    .fill(AuthTheme.skyBlue.opacity(isDark ? 0.12 : 0.18))
                    .frame(width: 240, height: 240)
                    .blur(radius: 30)
                    .offset(x: -70, y: -60)

                Circle()
                    .fill(AuthTheme.primaryBlue.opacity(isDark ? 0.14 : 0.10))
                    .frame(width: 220, height: 220)
                    .blur(radius: 32)
                    .offset(x: geo.size.width - 130, y: geo.size.height - 170)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 入力カード(白い角丸の板)

struct AuthCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let theme = AuthTheme(isDark: colorScheme == .dark)
        VStack(spacing: 14) {
            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(theme.isDark ? AuthTheme.skyBlue.opacity(0.20) : AuthTheme.primaryBlue.opacity(0.12),
                        lineWidth: 1.2)
        )
        .shadow(color: theme.isDark ? .black.opacity(0.35) : AuthTheme.primaryBlue.opacity(0.08),
                radius: 20, y: 8)
    }
}

// MARK: - 丸みのある入力欄(アイコン付き)
// ※ .focused(...) は、中に入れる入力欄の側で付ける

struct AuthField<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let iconColor: Color
    let isFocused: Bool
    private let content: Content

    init(icon: String, iconColor: Color, isFocused: Bool, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.isFocused = isFocused
        self.content = content()
    }

    var body: some View {
        let theme = AuthTheme(isDark: colorScheme == .dark)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(isFocused ? 0.22 : 0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            content
                .font(.system(size: 15.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.mainText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(isFocused ? theme.fieldFocused : theme.fieldIdle)
        )
        .overlay(
            Capsule().stroke(
                isFocused ? iconColor.opacity(0.75) : AuthTheme.primaryBlue.opacity(theme.isDark ? 0.16 : 0.08),
                lineWidth: isFocused ? 1.6 : 1)
        )
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}

// MARK: - パスワード入力(目のアイコンで表示/非表示)

struct AuthPasswordInput: View {
    @Environment(\.colorScheme) private var colorScheme
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType   // ログインは .password、新しく決めるときは .newPassword
    @State private var isVisible = false

    var body: some View {
        let theme = AuthTheme(isDark: colorScheme == .dark)
        HStack(spacing: 8) {
            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(contentType)

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .font(.subheadline)
                    .foregroundStyle(theme.subText.opacity(0.75))
            }
            .accessibilityLabel(isVisible ? "パスワードを隠す" : "パスワードを表示")
        }
    }
}

// MARK: - 確認コードの入力(数字だけ・最大10桁)

struct AuthCodeInput: View {
    @Binding var code: String

    var body: some View {
        TextField("確認コード(数字)", text: $code)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)   // メールで届いたコードをキーボードの上に出してくれる
            .onChange(of: code) { _, newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(10))
                if digits != newValue { code = digits }
            }
    }
}

// MARK: - メインのボタン(青いグラデーション)

struct AuthPrimaryButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        let isDark = colorScheme == .dark
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [AuthTheme.primaryBlue, AuthTheme.skyBlue],
                                   startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: AuthTheme.primaryBlue.opacity(isDark ? 0.35 : 0.26), radius: 10, y: 5)
        }
        .buttonStyle(PopPressButtonStyle())
        .disabled(isBusy || !isEnabled)
        .opacity(isBusy || !isEnabled ? 0.55 : 1.0)
    }
}

// 押し心地のあるボタンスタイル
struct PopPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - お知らせの帯(エラーは赤、案内は青)

struct AuthMessageBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    var isError = true

    var body: some View {
        let color: Color = isError ? .red : AuthTheme.primaryBlue
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "envelope.badge.fill")
                .foregroundStyle(color)
            Text(message)
                .font(.footnote)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.16 : 0.08))
        )
    }
}

// MARK: - 小さい文字のリンク風ボタン

struct AuthTextButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? AuthTheme.skyBlue : AuthTheme.primaryBlue)
    }
}

// MARK: - 入力のルール

enum AuthRule {
    // パスワードの最低の長さ(Supabase の Authentication > Providers > Email の設定と合わせる)
    static let passwordMinLength = 8
    static let displayNameMaxLength = 20

    // パスワードに問題があれば、その説明を返す(問題なければ nil)
    static func passwordProblem(_ password: String) -> String? {
        if password.count < passwordMinLength {
            return "パスワードは\(passwordMinLength)文字以上にしてください"
        }
        let hasLetter = password.contains { $0.isASCII && $0.isLetter }
        let hasNumber = password.contains { $0.isASCII && $0.isNumber }
        if !hasLetter || !hasNumber {
            return "パスワードには英字と数字の両方を入れてください"
        }
        return nil
    }

    // メールアドレスの形になっているか(届くかどうかは、確認コードで確かめる)
    static func looksLikeEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !email.contains(" ")
    }
}

extension String {
    // 前後の空白・改行を取ったもの(メールアドレスのコピペ対策)
    var authTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - エラーの文章

enum AuthErrorText {
    // Supabase のエラーの種類(例:invalid_credentials)
    static func code(of error: Error) -> String? {
        (error as? AuthError)?.errorCode.rawValue
    }

    // 画面に出す文章
    static func message(for error: Error, fallback: String) -> String {
        switch code(of: error) {
        case "invalid_credentials":
            return "メールアドレスかパスワードが違います"
        case "email_not_confirmed":
            return "メールアドレスの確認がまだ終わっていません。確認コードを入力してください"
        case "user_already_exists", "email_exists":
            return "このメールアドレスはすでに登録されています"
        case "weak_password":
            return "パスワードが簡単すぎます。もっと長く、複雑にしてください"
        case "otp_expired":
            return "確認コードがまちがっているか、期限が切れています"
        case "over_email_send_rate_limit", "over_request_rate_limit":
            return "短い時間に何度も送信されました。少し待ってからもう一度お試しください"
        case "email_address_invalid", "validation_failed":
            return "メールアドレスを確認してください"
        case "same_password":
            return "今までと同じパスワードは使えません"
        default:
            return fallback
        }
    }
}
