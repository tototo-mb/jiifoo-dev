import SwiftUI

//法人の申請画面
//入力で必要なもの->法人名、法人番号（13桁）

struct OrganizationApplyView: View{
    @Environment(\.dismiss) private var dismiss

    @State private var name = "" //法人名
    @State private var corporateNumber = "" //法人番号（13桁）
    @State private var isSubmitting = false //送信中か
    @State private var message: String? //結果のメッセージ
    @State private var isApplied = false //申請が成功したか

    //申請内容の記入漏れを確認
    private var isValid: Bool{
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && corporateNumber.count == 13 
        && corporateNumber.allSatisfy(\.isNumber)
        && !isSubmitting
    }

var body: some View{
    Form {
        Section{
            TextField("法人名", text: $name)
            TextField("法人番号（13桁）", text: $corporateNumber)
                .keyboardType(.numberPad)
    }footer: {
        Text("法人番号は国税庁の「法人番号公表サイト」で確認できます")
    }

        Section{
            Button{
                submit()
            } label: {
                if isSubmitting{
                    ProgressView()
                }else{
                    Text("申請")
                }
            }
            .disabled(!isValid)
        }
    }
        .navigationTitle("法人として申請")
        .navigationBarTitleDisplayMode(.inline)
        .alert(message ?? "", isPresented: Binding(
            get: { message != nil},
            set: {if !$0 { message = nil } }
        )){
            Button("OK") {
                if isApplied{ dismiss() } //申請が成功したら前の画面に戻る
            }
        }
    }
        //申請を送る
    private func submit(){
        isSubmitting = true
        Task{
            let result = (try? await JiifooAPI.applyOrganization(
                name: name, corporateNumber: corporateNumber)) ?? "error"
            isSubmitting = false

            switch result{
            case "ok":
                isApplied = true
                message = "申請が完了しました。審査が終了するまでお待ちください"
            case "invalid_name":
                message = "法人名を入力してください（100文字以内）"
            case "invalid_number":
                message = "法人番号は13桁の半角数字で入力してください"
            case "already_applied":
                message = "すでに申請中、または承認済みの法人があります"
            case "number_taken":
                message = "この法人番号はすでに登録されています"
            default:
                message = "申請できませんでした。通信状況を確認してください"
            }
        }
    }
}
    #Preview{
        NavigationStack{
            OrganizationApplyView()
        }
    }
