//
//  VoCalWidgetLiveActivity.swift
//  VoCalWidget
//
//  Created by Eric on 5/16/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct VoCalWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct VoCalWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoCalWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension VoCalWidgetAttributes {
    fileprivate static var preview: VoCalWidgetAttributes {
        VoCalWidgetAttributes(name: "World")
    }
}

extension VoCalWidgetAttributes.ContentState {
    fileprivate static var smiley: VoCalWidgetAttributes.ContentState {
        VoCalWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: VoCalWidgetAttributes.ContentState {
         VoCalWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: VoCalWidgetAttributes.preview) {
   VoCalWidgetLiveActivity()
} contentStates: {
    VoCalWidgetAttributes.ContentState.smiley
    VoCalWidgetAttributes.ContentState.starEyes
}
