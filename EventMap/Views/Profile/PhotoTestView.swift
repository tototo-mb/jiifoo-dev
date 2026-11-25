import SwiftUI

// 写真機能の動作確認用(設定画面の「開発用」から開く)
// 撮影 → 縮小・圧縮 → Supabase に保存 → 表示 までを単独で試す
// ※ 集合モードに組み込んだら、この画面と設定画面の入口は消す
struct PhotoTestView: View {
    @State private var userID: UUID?
    @State private var showCamera = false
    @State private var isUploading = false
    @State private var uploadedAt: UUID?        // 保存したら変わる(表示を読み込み直す)
    @State private var lastSizeText: String?
    @State private var message: String?

    // 到着の記念写真のスタンプを試す
    @State private var samplePhoto: UIImage?        // 試しに使う写真(保存はしない)
    @State private var showSampleCamera = false
    @State private var sampleStamped = false        // false → true で「ドン」と押す
    private let sampleStamp = ParticipationStamp(eventID: UUID(), title: "サンプルイベント",
                                                 organizerName: "主催者名", date: .now, isCorporate: false)

    var body: some View {
        Form {
            // ---- マイページのマスの形 ----
            Section {
                // 写真あり・なしを並べて見る(写真は下の「写真を撮って試す」などで用意する)
                HStack(alignment: .top, spacing: 12) {
                    CertificateTile(stamp: sampleStamp, photo: samplePhoto)
                    CertificateTile(stamp: sampleStamp, photo: nil)
                }
            } header: {
                Text("マイページのマスの形")
            } footer: {
                Text("左が写真あり、右が写真なしのイベントです。左の写真は、下の「写真を撮って試す」「地図の画像で試す」で用意できます。")
            }

            // ---- 到着の記念写真のスタンプ ----
            Section {
                Button {
                    showSampleCamera = true
                } label: {
                    Label("写真を撮って試す", systemImage: "camera")
                }
                Button {
                    Task {
                        // 渋谷駅のあたりの地図で試す
                        samplePhoto = PhotoCrop.centerCrop(
                            await VenueMapImage.make(center: .init(latitude: 35.6595, longitude: 139.7005)),
                            aspect: CertificateFrame.aspect)
                        pressSampleStamp()
                    }
                } label: {
                    Label("地図の画像で試す", systemImage: "map")
                }
                if let samplePhoto {
                    Image(uiImage: samplePhoto)
                        .resizable()
                        .scaledToFit()
                        .overlay {
                            CertificateFrameLayer(stamp: sampleStamp, isStamped: sampleStamped)
                        }
                        .listRowInsets(EdgeInsets())
                    Button("もう一度押す") { pressSampleStamp() }
                }
            } header: {
                Text("到着の記念写真のスタンプ")
            } footer: {
                Text("到着したときの記念写真と同じスタンプを試せます。ここで撮った写真は保存されません。")            
            }
            Section {
                Button {
                    showCamera = true
                } label: {
                    Label("写真を撮って保存する", systemImage: "camera")
                }
                .disabled(userID == nil || isUploading)

                if isUploading {
                    HStack {
                        ProgressView()
                        Text("保存中…")
                    }
                }
                if let lastSizeText {
                    LabeledContent("保存したサイズ", value: lastSizeText)
                }
            } footer: {
                Text("シミュレーターではカメラの代わりに写真ライブラリが開きます。")
            }

            if let userID {
                Section("保存した写真") {
                    StoredPhotoView(path: PhotoStorage.testPath(userID: userID), reloadID: uploadedAt)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())

                    Button("写真を削除する", role: .destructive) {
                        delete(userID: userID)
                    }
                }
            }
        }
        .navigationTitle("写真のテスト")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            userID = await JiifooAPI.currentUserID()
        }
        // スタンプを押した瞬間に「ドン」と振動
        .sensoryFeedback(.impact(weight: .heavy), trigger: sampleStamped)
        // スタンプを試す写真を撮る
        .fullScreenCover(isPresented: $showSampleCamera) {
            // 本番の記念写真と同じく、撮影枠を出して、同じ比率に切り抜く
            CameraPicker(onCapture: { image in
                samplePhoto = PhotoCrop.centerCrop(image, aspect: CertificateFrame.aspect)
                pressSampleStamp()
            }, guideAspect: CertificateFrame.aspect)
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                upload(image)
            }
            .ignoresSafeArea()
        }
        .alert(message ?? "", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
    }

    // サンプルのスタンプを、もう一度「ドン」と押す
    private func pressSampleStamp() {
        sampleStamped = false
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                sampleStamped = true
            }
        }
    }

    private func upload(_ image: UIImage) {
        guard let userID else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                if let data = PhotoStorage.compress(image) {
                    lastSizeText = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                }
                try await PhotoStorage.upload(image, to: PhotoStorage.testPath(userID: userID))
                uploadedAt = UUID()
            } catch {
                message = "保存できませんでした"
                print("写真の保存に失敗:", error)
            }
        }
    }

    private func delete(userID: UUID) {
        Task {
            do {
                try await PhotoStorage.delete(path: PhotoStorage.testPath(userID: userID))
                uploadedAt = UUID()
                lastSizeText = nil
            } catch {
                message = "削除できませんでした"
                print("写真の削除に失敗:", error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PhotoTestView()
    }
}
