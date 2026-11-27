import SwiftUI
import CoreLocation

// 位置情報が使えないときの警告
// ・地図の現在地ボタンのすぐ上に、警告マークのボタンを出す(EventMapView の controlButtons)
// ・押すと、警告文と理由、「設定を開く」ボタンのポップアップを出す
// ・その状態に初めてなったときだけ、ポップアップを自動で開く
// ・設定アプリで許可して戻ってくると、LocationManager が気づいてボタンが消える

// MARK: - 位置情報が使えない理由

enum LocationPermissionProblem: String {
    case denied           // このアプリに位置情報を許可しなかった
    case restricted       // スクリーンタイムなどの制限で、本人が変えられない
    case servicesOff      // iPhone 全体の位置情報サービスがオフ
    case reducedAccuracy  // 許可はしているが「正確な位置情報」がオフ(数km ずれるので到着を確かめられない)

    // ポップアップの見出し
    var title: String {
        switch self {
        case .denied:          return "位置情報がオフになっています"
        case .restricted:      return "位置情報が制限されています"
        case .servicesOff:     return "iPhone の位置情報サービスがオフです"
        case .reducedAccuracy: return "正確な位置情報がオフです"
        }
    }

    // ポップアップの本文(警告文と理由)
    var message: String {
        switch self {
        case .denied:
            return Self.reasons + "\n\n「設定を開く」→「位置情報」で、「このAppの使用中」を選んでください。"
        case .restricted:
            return Self.reasons + "\n\nスクリーンタイムなどの制限で、このiPhoneでは変更できない場合があります。iPhone を管理している人に確認してください。"
        case .servicesOff:
            return Self.reasons + "\n\n設定アプリの「プライバシーとセキュリティ」→「位置情報サービス」をオンにしてから、jiifoo を「このAppの使用中」にしてください。"
        case .reducedAccuracy:
            return "おおよその位置しかわからないため、会場に着いたことを確かめられません。\n\n「設定を開く」→「位置情報」で、「正確な位置情報」をオンにしてください。"
        }
    }

    // 画面上部の帯に出す短い警告文
    var bannerText: String {
        switch self {
        case .denied:          return "位置情報がオフのため、近くのイベントを表示できません"
        case .restricted:      return "位置情報が制限されているため、近くのイベントを表示できません"
        case .servicesOff:     return "位置情報サービスがオフのため、近くのイベントを表示できません"
        case .reducedAccuracy: return "正確な位置情報がオフのため、会場への到着を確認できません"
        }
    }

    // 位置情報を使う理由(共通)
    private static let reasons = """
        jiifoo では位置情報を次のことに使います。
        ・近くで開催されるイベントを地図に表示する
        ・会場に着いたことを確かめて、到着スタンプを押す

        位置情報はこの2つにだけ使い、ほかの人に現在地が公開されることはありません。
        """

    // 「設定を開く」ボタンを出すか(制限されているときは、本人が設定で変えられないので出さない)
    var canOpenSettings: Bool { self != .restricted }

    // ボタンの色(「正確な位置情報」だけは、使えなくはないので弱めの色)
    var backgroundColor: Color { self == .reducedAccuracy ? .yellow : .orange }
    var iconColor: Color { self == .reducedAccuracy ? .black : .white }
}

// MARK: - 警告ボタン(押すとポップアップ)

struct LocationWarningButton: View {
    let problem: LocationPermissionProblem
    @Binding var showsPopup: Bool   // ポップアップを開いているか(上の帯を押したときも開くので、地図の画面と共有する)

    @Environment(LocationManager.self) private var locationManager
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button {
            showsPopup = true
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(problem.iconColor)
                .frame(width: 50, height: 50)
                .background(problem.backgroundColor, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 3)
        }
        .accessibilityLabel(problem.title)
        .accessibilityHint("押すと理由と設定の開き方を表示します")
        .alert(problem.title, isPresented: $showsPopup) {
            if problem.canOpenSettings {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)   // 設定アプリの jiifoo の画面が開く
                    }
                }
            }
            Button("閉じる", role: .cancel) { }
        } message: {
            Text(problem.message)
        }
        // 初めてこの状態になったときだけ、自動で開く
        .onAppear(perform: autoShowIfFirstTime)
        .onChange(of: problem) { _, _ in
            autoShowIfFirstTime()
        }
        // 設定アプリから戻ってきたら、iPhone 全体の位置情報サービスがオンになったか確かめ直す
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await locationManager.refreshServicesEnabled() }
            }
        }
    }

    // 状態ごとに1回だけ自動で開く(一度見た人には、アイコンだけを出す)
    private func autoShowIfFirstTime() {
        let key = "didAutoShowLocationWarning.\(problem.rawValue)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task {
            try? await Task.sleep(for: .seconds(0.6))   // 地図が表示されてから出す
            showsPopup = true
        }
    }
}

// MARK: - 画面上部の警告の帯(押すと、警告ボタンと同じポップアップを開く)

struct LocationWarningBanner: View {
    let problem: LocationPermissionProblem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(problem.iconColor)
                    .frame(width: 28, height: 28)
                    .background(problem.backgroundColor, in: Circle())
                Text(problem.bannerText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(problem.backgroundColor.opacity(0.8), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityHint("押すと理由と設定の開き方を表示します")
    }
}

#Preview {
    VStack(spacing: 12) {
        LocationWarningBanner(problem: .denied) { }
        LocationWarningBanner(problem: .reducedAccuracy) { }
        LocationWarningButton(problem: .denied, showsPopup: .constant(false))
        LocationWarningButton(problem: .reducedAccuracy, showsPopup: .constant(false))
    }
    .environment(LocationManager())
}

