import SwiftUI
import RiveRuntime

//法人ユーザー用ピン
struct BusinessPinView: View {
    let isJoinable: Bool

    @StateObject private var riveViewModel1 = RiveViewModel(
        fileName: "Fire",
        stateMachineName: "State Machine 1",
        artboardName: "FireParticleSystem"
    )

@State private var isLoaded=false
    
    var body: some View {
        riveViewModel1.view()
            .frame(width: 60, height: 60)
            .saturation(isJoinable ? 1 : 0)
            .opacity(isJoinable ? 1 : 0.6)
    }
}

struct PrivatePinView:View{
    let isJoinable: Bool
    
    @StateObject private var riveViewModel2 = RiveViewModel(
        fileName:"dopa_fire",
        stateMachineName:"State Machine 1",
        artboardName:"FireParticleSystem"
    )
    
@State private var isLoaded=false
    
    var body:some View{
        riveViewModel2.view()
            .frame(width: 60, height: 60)
            .saturation(isJoinable ? 1 : 0)
            .opacity(isJoinable ? 1 : 0.6)
    }
}


#Preview {
    BusinessPinView(isJoinable: true)
    PrivatePinView(isJoinable: true)
}

