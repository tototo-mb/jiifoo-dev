import SwiftUI

// イベント詳細の「イベントの様子」(途中参加OK型の開催中だけ)
// 参加者が「みんなに公開」した写真を、誰でも見られる
// 主催者には、通報の数を出す(写真を開くと「非公開にする」ができる)
struct EventPublicPhotosSection: View {
    let event: Event
    @Environment(EventStore.self) private var eventStore

    @State private var photos: [PublicPhoto] = []
    @State private var viewingPhoto: PublicPhoto?    // 大きく表示している写真

    private var isOrganizer: Bool { eventStore.isMine(event) }

    var body: some View {
        Section {
            if photos.isEmpty {
                Text("まだ公開された写真はありません")
                    .foregroundStyle(.secondary)
            } else {
                // 横にスクロールして見る
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(photos) { photo in
                            Button {
                                viewingPhoto = photo
                            } label: {
                                StoredPhotoView(path: photo.path)
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    // 主催者には通報の数
                                    .overlay(alignment: .topTrailing) {
                                        if isOrganizer && photo.reportCount > 0 {
                                            Label("\(photo.reportCount)", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption2.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(.red, in: Capsule())
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("イベントの様子")
        } footer: {
            Text("参加者が公開した写真です。開催中だけ見られます")
        }
        .task {
            await loadPhotos()
        }
        .sheet(item: $viewingPhoto) { photo in
            PublicPhotoDetailView(photo: photo, isOrganizer: isOrganizer) {
                await loadPhotos()   // 非公開にしたら読み直す
            }
        }
    }

    // 公開中の写真を読み込む
    private func loadPhotos() async {
        if let list = try? await JiifooAPI.eventPublicPhotos(eventId: event.id) {
            photos = list
        }
    }
}

// 公開写真を大きく表示する画面(通報・非公開にする)
struct PublicPhotoDetailView: View {
    let photo: PublicPhoto
    let isOrganizer: Bool
    var onHidden: () async -> Void     // 非公開にしたあとに呼ぶ(一覧を読み直すため)

    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false
    @State private var showHide = false
    @State private var message: String?

    // 通報の理由
    private let reasons = ["不適切な内容", "無断で撮影されている", "その他"]

    var body: some View {
        NavigationStack {
            StoredPhotoView(path: photo.path, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("イベントの様子")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
                // 画面下のボタン(自分の写真 / 主催者 / それ以外 で変わる)
                .safeAreaInset(edge: .bottom) {
                    bottomButton
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
                .confirmationDialog("この写真を通報しますか？",
                                    isPresented: $showReport,
                                    titleVisibility: .visible) {
                    ForEach(reasons, id: \.self) { reason in
                        Button(reason) { report(reason) }
                    }
                } message: {
                    Text("通報した人の名前は、ほかの人には表示されません")
                }
                .confirmationDialog("この写真を非公開にしますか？",
                                    isPresented: $showHide,
                                    titleVisibility: .visible) {
                    Button("非公開にする", role: .destructive) { hide() }
                } message: {
                    Text("撮った人以外は見られなくなります")
                }
                .alert(message ?? "", isPresented: Binding(
                    get: { message != nil },
                    set: { if !$0 { message = nil } }
                )) {
                    Button("OK", role: .cancel) { }
                }
        }
    }

    @ViewBuilder
    private var bottomButton: some View {
        if photo.isMine {
            Text("あなたが公開した写真です")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if isOrganizer {
            VStack(spacing: 6) {
                if photo.reportCount > 0 {
                    Text("\(photo.reportCount)件の通報があります")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("非公開にする", role: .destructive) { showHide = true }
            }
        } else {
            Button("通報する", role: .destructive) { showReport = true }
        }
    }

    // 通報する
    private func report(_ reason: String) {
        Task {
            let result = (try? await JiifooAPI.reportPhoto(path: photo.path, reason: reason)) ?? "error"
            message = result == "ok"
                ? "通報が完了しました。"
                : "通報できませんでした(\(result))"
        }
    }

    // 主催者が非公開にする
    private func hide() {
        Task {
            let result = (try? await JiifooAPI.hidePhoto(path: photo.path)) ?? "error"
            if result == "ok" {
                await onHidden()
                dismiss()
            } else {
                message = "非公開にできませんでした(\(result))"
            }
        }
    }
}
