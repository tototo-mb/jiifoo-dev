//
//  ScreenEdgeVIew.swift
//  jiifoo
//
//  Created by 高山椋 on 2026/10/21.
//
import SwiftUI
import RiveRuntime

// 画面のふちに色を出す演出
struct ScreenEdgeGlowView: View {
    @StateObject private var riveViewModel = RiveViewModel(
        fileName: "rgbaura",
        stateMachineName: "State Machine 1",// ふち演出のステートマシン名
        fit: .fill,// 画面いっぱいに引き伸ばす
        artboardName: "RGB"      // ふち演出のアートボード名に合わせる
                                     
    )

    var body: some View {
        riveViewModel.view()
            .ignoresSafeArea()
            .blur(radius: 10)
            .allowsHitTesting(false)   // 下の地図の操作を邪魔しない
    }
}
