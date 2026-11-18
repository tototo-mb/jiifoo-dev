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

    var body: some View {
        Form {
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
