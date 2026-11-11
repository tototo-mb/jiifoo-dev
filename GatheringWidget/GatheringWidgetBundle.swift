//
//  GatheringWidgetBundle.swift
//  GatheringWidget
//
//  Created by 高山椋 on 2026/11/10.
//

import WidgetKit
import SwiftUI

@main
struct GatheringWidgetBundle: WidgetBundle {
    var body: some Widget {
        GatheringWidget()
        GatheringWidgetControl()
        GatheringWidgetLiveActivity()
    }
}
