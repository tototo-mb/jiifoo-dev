//
//  SupabaseTestView.swift
//  jiifoo
//
//  Supabase との接続を確かめるための一時的なテスト画面
//  ※動作確認が終わったら削除してよい
//

import SwiftUI
import CoreLocation

struct SupabaseTestView: View {

    // 入力欄
    @State private var email = ""
    @State private var password = "password123"
    @State private var displayName = "テスト1"

    // 結果
    @State private var log: [String] = []
    @State private var nearby: [EventPin] = []
    @State private var isBusy = false

    // 現在地(iPhone の位置情報を使う)
    @State private var locationManager = LocationManager()

    // テスト用の座標:現在地がわかればそこ、わからなければ東京駅
    private var testLat: Double { locationManager.userLocation?.latitude ?? 35.681236 }
    private var testLng: Double { locationManager.userLocation?.longitude ?? 139.767125 }
    private var hasLocation: Bool { locationManager.userLocation != nil }

    var body: some View {
        NavigationStack {
            List {
                Section("アカウント") {
                    TextField("メールアドレス", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("パスワード", text: $password)
                    TextField("表示名", text: $displayName)

                    Button("① 新規登録") {
                        run("新規登録") {
                            try await JiifooAPI.signUp(email: email, password: password, displayName: displayName)
                            return "登録しました"
                        }
                    }
                    Button("② ログイン") {
                        run("ログイン") {
                            try await JiifooAPI.signIn(email: email, password: password)
                            return "ログインしました"
                        }
                    }
                    Button("③ 自分のプロフィールを読む") {
                        run("プロフィール") {
                            let p = try await JiifooAPI.myProfile()
                            return "表示名: \(p.displayName)"
                        }
                    }
                    Button("ログアウト", role: .destructive) {
                        run("ログアウト") {
                            try await JiifooAPI.signOut()
                            return "ログアウトしました"
                        }
                    }
                }

                Section("イベント") {
                    // 今どこを基準にしているかの表示
                    if hasLocation {
                        Label(String(format: "現在地: %.5f, %.5f", testLat, testLng),
                              systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("現在地を取得中…(取得できないときは東京駅を使います)",
                              systemImage: "location.slash")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Button("④ 30分後に始まるイベントを作る") {
                        run("イベント作成") {
                            let id = try await JiifooAPI.createEvent(
                                title: "テストイベント",
                                category: "ramen",
                                description: "接続テスト用",
                                placeName: hasLocation ? "テスト用の集合場所" : "東京駅 丸の内北口",
                                latitude: testLat,
                                longitude: testLng,
                                startsAt: Date().addingTimeInterval(30 * 60),
                                capacity: 3,
                                organizationId:  nil
                            )
                            return "作成しました ID: \(id.uuidString.prefix(8))…"
                        }
                    }
                    Button("⑤ 近くのイベントを探す") {
                        run("近くのイベント") {
                            nearby = try await JiifooAPI.nearbyEvents(latitude: testLat, longitude: testLng)
                            return "\(nearby.count) 件見つかりました"
                        }
                    }
                }

                if !nearby.isEmpty {
                    Section("見つかったイベント(タップで予約)") {
                        ForEach(nearby) { event in
                            Button {
                                run("予約") {
                                    let result = try await JiifooAPI.reserve(eventId: event.id)
                                    return "\(event.title): \(result)"
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(event.title).font(.headline)
                                    Text("\(event.placeName) ・ \(event.participantCount)/\(event.capacity.map { "\($0)" } ?? "上限なし")人 ・ \(Int(event.distanceM))m")                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(event.startsAt, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("ログ") {
                    if log.isEmpty {
                        Text("まだ何もしていません").foregroundStyle(.secondary)
                    }
                    ForEach(Array(log.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Supabase テスト")
            .disabled(isBusy)
            .overlay {
                if isBusy { ProgressView() }
            }
        }
    }

    // ボタンの処理を実行して、結果やエラーをログに出す
    private func run(_ label: String, _ action: @escaping () async throws -> String) {
        isBusy = true
        Task {
            do {
                let message = try await action()
                log.append("✅ \(label): \(message)")
            } catch {
                log.append("❌ \(label): \(error)")
                print("❌ \(label):", error)
            }
            isBusy = false
        }
    }
}

#Preview {
    SupabaseTestView()
}
