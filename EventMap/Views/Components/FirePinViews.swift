import SwiftUI
import RiveRuntime

struct FirePinView: View {
    let isJoinable: Bool

    @StateObject private var riveViewModel = RiveViewModel(
        fileName: "Fire",
        stateMachineName: "State Machine 1",
        artboardName: "FireParticleSystem"
    )

    var body: some View {
        riveViewModel.view()
            .frame(width: 60, height: 60)
            .saturation(isJoinable ? 1 : 0)
            .opacity(isJoinable ? 1 : 0.6)
    }
}

#Preview {
    FirePinView(isJoinable: true)
}
