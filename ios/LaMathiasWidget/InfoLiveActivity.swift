import ActivityKit
import SwiftUI
import WidgetKit

private func tint(_ s: InfoAttributes.ContentState) -> Color { let c = LMInfo.rgb(s.tone); return Color(red: c.0, green: c.1, blue: c.2) }

struct InfoGauge: View {
    let p: Double
    let col: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(col).frame(width: max(6, g.size.width * CGFloat(max(0, min(1, p)))))
            }
        }.frame(height: 7)
    }
}

struct InfoLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: InfoAttributes.self) { ctx in
            let s = ctx.state
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: LMInfo.symbol(s.icon)).font(.system(size: 26, weight: .bold)).foregroundColor(tint(s))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title).font(.system(size: 17, weight: .bold, design: .rounded))
                        if !s.sub.isEmpty { Text(s.sub).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7)) }
                    }
                    Spacer()
                    if !s.right.isEmpty { Text(s.right).font(.system(size: 22, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(tint(s)) }
                }
                if let p = s.progress { InfoGauge(p: p, col: tint(s)) }
            }
            .padding(16)
            .foregroundColor(.white)
            .activityBackgroundTint(Color(red: 0.04, green: 0.03, blue: 0.12))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: LMInfo.symbol(s.icon)).font(.system(size: 30, weight: .bold)).foregroundColor(tint(s)).padding(.leading, 6).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !s.right.isEmpty { Text(s.right).font(.system(size: 24, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(tint(s)).padding(.trailing, 6).padding(.top, 6) }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(s.title).font(.system(size: 16, weight: .bold, design: .rounded)).lineLimit(1)
                        if !s.sub.isEmpty { Text(s.sub).font(.system(size: 12.5, weight: .medium, design: .rounded)).foregroundColor(.secondary).lineLimit(2).multilineTextAlignment(.center) }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let p = s.progress { InfoGauge(p: p, col: tint(s)).padding(.horizontal, 10).padding(.top, 4) }
                }
            } compactLeading: {
                Image(systemName: LMInfo.symbol(s.icon)).foregroundColor(tint(s))
            } compactTrailing: {
                Text(s.right.isEmpty ? s.title : s.right).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(tint(s)).lineLimit(1).frame(maxWidth: 90)
            } minimal: {
                Image(systemName: LMInfo.symbol(s.icon)).foregroundColor(tint(s))
            }
        }
    }
}
