import SwiftUI

// マイページ上部（アイコン・数字・自己紹介）
struct ProfileHeaderView: View {
    let name: String
    let bio: String
    let postedCount: Int
    let joinedCount: Int
    let followerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                // アイコン（仮：名前の1文字目）
                Text(String(name.prefix(1)))
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 84)
                    .background(Color.blue.gradient, in: Circle())

                HStack {
                    statItem(count: postedCount, label: "掲載")
                    statItem(count: joinedCount, label: "参加予定")
                    statItem(count: followerCount, label: "フォロワー")
                }
            }

            Text(name)
                .font(.headline)
            Text(bio)
                .font(.subheadline)

            Button {
                // プロフィール編集（後で作成）
            } label: {
                Text("プロフィールを編集")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(.horizontal)
    }

    private func statItem(count: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ProfileHeaderView(name: "xxxx", bio: "xxxxxx", postedCount: 1, joinedCount: 2, followerCount: 0)
}
