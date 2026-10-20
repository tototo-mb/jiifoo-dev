import SwiftUI

// 汎用ビュー（まだ作っていない画面の仮置き用）
// ※ 別ファイルから使うので fileprivate は外しています
struct AnotherView: View {
    var textContent: String

    var body: some View {
        NavigationStack {
            VStack {
                Text(textContent)
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }
}
