//
//  VoCalWidgetBundle.swift
//  VoCalWidget
//
//  Created by Eric on 5/16/26.
//

import WidgetKit
import SwiftUI

@main
struct VoCalWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoCalWidget()
        VoCalWidgetControl()
        VoCalWidgetLiveActivity()
    }
}
