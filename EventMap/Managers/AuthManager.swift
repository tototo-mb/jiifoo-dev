import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class AuthManager{
    var isLoggedIn=false
    var isChecking=true
    func startListening() async{
        for await(_,session) in supabase.auth.authStateChanges{
            isLoggedIn = session != nil
            isChecking=false
        }
    }
}
