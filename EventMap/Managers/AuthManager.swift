import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthManager{
    var isLoggedIn=false
    var isChecking=true
    
    //法人として投稿できる法人の一覧、個人ユーザーなら空
    var organizations:[Organization]=[]
    var isCorporate:Bool{ !organizations.isEmpty }
    
    func startListening() async{
        for await(_,session) in supabase.auth.authStateChanges{
            isLoggedIn = session != nil
            
            //法人としてログインしたら一覧を取得、ログアウトしたらからにする
            if session != nil {
                organizations=(try? await JiifooAPI.myPostableOrganizations()) ?? []
            }else{
                organizations=[]
            }
            
            //法人か個人か判定してから画面を出す
            isChecking=false
        }
    }
}
