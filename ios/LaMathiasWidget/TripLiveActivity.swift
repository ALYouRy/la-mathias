import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LaMathiasWidgets: WidgetBundle {
    var body: some Widget {
        TripLiveActivity()
        InfoLiveActivity()
    }
}

private func col(_ s: TripAttributes.ContentState) -> Color {
    let c = LMFmt.rgb(s)
    return Color(red: c.0, green: c.1, blue: c.2)
}

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripAttributes.self) { ctx in
            LockScreenView(s: ctx.state)
                .activityBackgroundTint(Color(red: 0.04, green: 0.03, blue: 0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(s.speed)").font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit()
                        Text(s.gear != nil ? "km/h · \(s.gear!)\(s.gear == 1 ? "re" : "e")" : "km/h").font(.caption2).foregroundColor(.secondary)
                    }.padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(LMFmt.consText(s)).font(.system(size: 34, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(col(s))
                        Text(s.cut ? "coupure" : LMFmt.consUnit(s)).font(.caption2).foregroundColor(.secondary)
                    }.padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(LMFmt.n1(s.km) + " km")
                        Spacer()
                        Text("moy. " + (s.avg != nil ? LMFmt.n1(s.avg!) : "–"))
                        Spacer()
                        Text("\(s.minutes) min")
                        if let c = s.cost { Spacer(); Text(String(format: "%.2f €", c).replacingOccurrences(of: ".", with: ",")) }
                    }.font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().padding(.horizontal, 6)
                }
            } compactLeading: {
                Text("\(s.speed)").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
            } compactTrailing: {
                Text(LMFmt.consText(s)).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(col(s))
            } minimal: {
                Text(LMFmt.consText(s)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(col(s))
            }
        }
    }
}

struct LockScreenView: View {
    let s: TripAttributes.ContentState
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(s.speed)").font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit()
                    Text("km/h").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(LMFmt.consText(s)).font(.system(size: 38, weight: .heavy, design: .rounded)).monospacedDigit().foregroundColor(col(s))
                    Text(s.cut ? "coupure d’injection" : LMFmt.consUnit(s)).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack {
                Label(LMFmt.n1(s.km) + " km", systemImage: "car.fill")
                Spacer()
                Text("moy. " + (s.avg != nil ? LMFmt.n1(s.avg!) + " L/100" : "–"))
                Spacer()
                Text("\(s.minutes) min")
            }.font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundColor(.white.opacity(0.85))
        }
        .padding(16)
        .foregroundColor(.white)
    }
}
