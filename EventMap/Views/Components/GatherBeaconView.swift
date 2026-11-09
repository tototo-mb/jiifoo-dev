import SwiftUI

// 集合場所の目印(光の柱)
// 地面に広がる波紋 + 上に伸びる光の柱 + 根元の光る点
// 地図の Annotation で anchor: .bottom にすると、柱の根元が集合場所に来る
struct GatherBeaconView: View {
    var color: Color = .orange

    @State private var isPulsing = false   // 波紋が広がる
    @State private var isGlowing = false   // 柱がゆっくり明るくなったり暗くなったりする

    var body: some View {
        ZStack(alignment: .bottom) {
            // ① 地面に広がる波紋(2重にして、少しずらして広げる)
            ForEach(0..<2) { i in
                Ellipse()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 70, height: 22)
                    .scaleEffect(isPulsing ? 1.5 : 0.4)
                    .opacity(isPulsing ? 0 : 0.9)
                    .animation(
                        .easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i)),
                        value: isPulsing
                    )
                    .offset(y: 11)   // 楕円の中心を根元に合わせる
            }

            // ② 光の柱(外側のぼんやりした光 + 内側の明るい芯)
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0), color.opacity(0.5)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 150)
                    .blur(radius: 6)
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.9), color],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 140)
            }
            .opacity(isGlowing ? 1 : 0.6)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: isGlowing)

            // ③ 根元の光る点
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: color, radius: 8)
                .offset(y: 7)
        }
        .frame(width: 110, height: 160, alignment: .bottom)
        .allowsHitTesting(false)          // 地図の操作のじゃまをしない
        .accessibilityLabel("集合場所")
        .onAppear {
            isPulsing = true
            isGlowing = true
        }
    }
}

#Preview {
    GatherBeaconView()
        .padding(40)
        .background(.gray.opacity(0.3))
}
