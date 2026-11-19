import SwiftUI

// 思い出の写真を撮る画面(1人1イベント最大5枚。撮り直し・削除ができる)
struct MemoryCameraView: View {
    let eventID: UUID
    let eventTitle: String

    @Environment(\.dismiss) private var dismiss
    @State private var paths: [String] = []              // 自分が撮った写真(古い順)
    @State private var reloadIDs: [String: UUID] = [:]   // 撮り直した写真の表示を読み直すため
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var showCamera = false
    @State private var retakingPath: String?             // 撮り直す写真(nil なら新しく撮る)
    @State private var selectedPath: String?             // 押した写真(撮り直し・削除を選ぶ)
    @State private var message: String?

    // あと何枚撮れるか
    private var remaining: Int { max(0, PhotoStorage.maxMemoryPhotos - paths.count) }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(paths, id: \.self) { path in
                        Button {
                            selectedPath = path
                        } label: {
                            StoredPhotoView(path: path, reloadID: reloadIDs[path])
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .overlay {
                if isLoading || isSaving {
                    ProgressView()
                } else if paths.isEmpty {
                    ContentUnavailableView("まだ写真がありません",
                                           systemImage: "camera",
                                           description: Text("最大\(PhotoStorage.maxMemoryPhotos)枚まで撮影できます"))
                }
            }
            .navigationTitle(eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            // 画面下に撮影ボタンを固定
            .safeAreaInset(edge: .bottom) {
                Button {
                    retakingPath = nil
                    showCamera = true
                } label: {
                    Label(remaining > 0 ? "撮影する(あと\(remaining)枚)" : "撮影できる枚数に達しました",
                          systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(remaining == 0 || isSaving || isLoading)
                .padding()
                .background(.bar)
            }
            // 写真を押したら「撮り直す / 削除する」を選ぶ
            .confirmationDialog("この写真をどうしますか？",
                                isPresented: Binding(
                                    get: { selectedPath != nil },
                                    set: { if !$0 { selectedPath = nil } }),
                                titleVisibility: .visible,
                                presenting: selectedPath) { path in
                Button("撮り直す") {
                    retakingPath = path
                    showCamera = true
                }
                Button("削除する", role: .destructive) {
                    delete(path)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    save(image)
                }
                .ignoresSafeArea()
            }
            .alert(message ?? "", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { }
            }
            .task {
                await loadPaths()
            }
        }
    }

    // MARK: - 処理

    // このイベントで自分が撮った写真を読み込む
    private func loadPaths() async {
        isLoading = true
        defer { isLoading = false }
        do {
            paths = try await JiifooAPI.myPhotoPaths(eventId: eventID)
        } catch {
            message = "写真を読み込めませんでした"
            print("思い出の写真の読み込みに失敗:", error)
        }
    }

    // 撮った写真を保存する(撮り直しなら上書き、そうでなければ1枚増やす)
    private func save(_ image: UIImage) {
        let retaking = retakingPath
        isSaving = true
        Task {
            do {
                if let retaking {
                    try await PhotoStorage.retakeMemoryPhoto(image, path: retaking)
                    reloadIDs[retaking] = UUID()   // その写真の表示だけ読み直す
                } else {
                    let path = try await PhotoStorage.addMemoryPhoto(image, eventID: eventID)
                    paths.append(path)
                }
            } catch {
                message = error.localizedDescription
                print("思い出の写真の保存に失敗:", error)
            }
            isSaving = false
        }
    }

    // 写真を消す
    private func delete(_ path: String) {
        isSaving = true
        Task {
            do {
                try await PhotoStorage.deleteMemoryPhoto(path: path)
                paths.removeAll { $0 == path }
            } catch {
                message = "写真を削除できませんでした"
                print("思い出の写真の削除に失敗:", error)
            }
            isSaving = false
        }
    }
}

#Preview {
    MemoryCameraView(eventID: UUID(), eventTitle: "サンプルイベント")
}
