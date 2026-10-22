import SwiftUI

struct LoginView:View{
    
    @State private var email=""
    @State private var password=""
    @State private var displayName=""
    @State private var isSignUp=false
    @State private var errorMessage:String?
    @State private var isBusy=false
    
    
    var body :some View{
        VStack(spacing:16){
            Text("jiifoo")
                .font(.largeTitle)
            Picker("モード",selection:$isSignUp){
                Text("ログイン").tag(false)
                Text("新規登録").tag(true)
            }
            .pickerStyle(.segmented)
            
            TextField("メールアドレス",text:$email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
            SecureField("パスワード",text:$password)
            
            if isSignUp{
                TextField("表示名",text:$displayName)
            }
            if let errorMessage{
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
            Button(isSignUp ? "新規登録":"ログイン"){
                submit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }
    private func submit(){
        Task{
            isBusy=true
            errorMessage=nil
            do{
                if isSignUp{
                    try await JiifooAPI.signUp(email:email,password:password,displayName: displayName)
                }else {
                    try await JiifooAPI.signIn(email: email,password: password)
                }
            }catch{
                errorMessage="入力内容に誤りがあります。内容を確認してください"
            }
            isBusy=false
        }
    }

}

