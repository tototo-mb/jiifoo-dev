import SwiftUI
import UIKit

// キーボードのすぐ上に「閉じる」ボタンを出す
// 使い方:画面(Form や VStack など)に .keyboardCloseButton() を付けるだけ
// その画面のどの入力欄でキーボードが出ていても、押すと閉じる
struct KeyboardCloseButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()   // ボタンを右はしに寄せる
                    Button("閉じる") { closeKeyboard() }
                }
            }
    }

    // 今入力している欄に「入力をやめて」と伝える(=キーボードが閉じる)
    private func closeKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

extension View {
    /// キーボードの上に「閉じる」ボタンを付ける
    func keyboardCloseButton() -> some View {
        modifier(KeyboardCloseButton())
    }
}