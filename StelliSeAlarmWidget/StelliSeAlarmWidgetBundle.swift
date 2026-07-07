//
//  StelliSeAlarmWidgetBundle.swift
//  StelliSeAlarmWidget
//
//  Created by yuu on 2026/06/29.
//

import WidgetKit
import SwiftUI

@main
struct StelliSeAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        StelliSeAlarmWidget()
        StelliSeAlarmWidgetLiveActivity()
    }
}
