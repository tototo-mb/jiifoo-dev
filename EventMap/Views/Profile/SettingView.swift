import SwiftUI
import Supabase

// 設定画面(マイページ右上の歯車から開く)
// 設定の項目が増えたら、ここに Section を足していく
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // マップに「参加できる範囲(800m)」を表示するか
    // EventMapView でも同じ名前で読んでいるので、ここで変えるとすぐ反映される
    @AppStorage("showJoinableRange") private var showJoinableRange = true

    @State private var email: String?
    @State private var showLogoutDialog = false

    // アプリのバージョン(Xcode の設定から自動で取得)
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        NavigationStack {
            Form {
                // ---- アカウント ----
                Section("アカウント") {
                    LabeledContent("メールアドレス", value: email ?? "読み込み中…")
                }

                // ---- 表示 ----
                Section {
                    Toggle(isOn: $showJoinableRange) {
                        Label("参加できる範囲を表示", systemImage: "circle.dashed")
                    }
                } header: {
                    Text("マップの表示")
                } footer: {
                    Text("マップに、現在地から\(Int(LocationManager.joinableRadius))m(参加できる範囲)の円を表示します。")
                }

                // ---- アプリについて ----
                Section("アプリについて") {
                    LabeledContent("バージョン", value: appVersion)
                    // 利用規約・プライバシーポリシーのページができたら URL を差し替える
                    Link("利用規約", destination: URL(string: "https://jiifoo.com/terms")!)
                    Link("プライバシーポリシー", destination: URL(string: "https://jiifoo.com/privacy")!)
                }

                // ---- ログアウト ----
                Section {
                    Button("ログアウト", role: .destructive) {
                        showLogoutDialog = true
                    }
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .confirmationDialog("ログアウトしますか？",
                                isPresented: $showLogoutDialog,
                                titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) {
                    Task {
                        try? await JiifooAPI.signOut()
                        // ログイン画面への切り替えは AuthManager が自動で行う
                    }
                }
            }
            .task {
                email = try? await supabase.auth.session.user.email
            }
        }
    }
}

#Preview {
    SettingsView()
}
