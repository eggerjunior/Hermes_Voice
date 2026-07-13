import ActivityKit
import SwiftUI
import WidgetKit

@main
struct HermesVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        HermesStatusWidget()
        HermesLiveActivityWidget()
    }
}

struct HermesStatusWidget: Widget {
    let kind = "HermesStatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HermesStatusProvider()) { entry in
            HermesStatusWidgetView(entry: entry)
                .containerBackground(Color.black, for: .widget)
        }
        .configurationDisplayName("Hermes Voice")
        .description("Status rápido do Hermes para conversas por voz.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct HermesStatusEntry: TimelineEntry {
    let date: Date
    let status: String
    let detail: String
}

struct HermesStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> HermesStatusEntry {
        HermesStatusEntry(date: Date(), status: "Pronto", detail: "Assistente de voz")
    }

    func getSnapshot(in context: Context, completion: @escaping (HermesStatusEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HermesStatusEntry>) -> Void) {
        let entry = HermesStatusEntry(date: Date(), status: "Pronto", detail: "Chame pelo app ou Siri")
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct HermesStatusWidgetView: View {
    let entry: HermesStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.mint)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes")
                    .font(.headline)
                Text(entry.status)
                    .font(.caption)
                    .foregroundStyle(.mint)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.mint)
                    Spacer()
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                }

                Spacer()

                Text("Hermes Voice")
                    .font(.headline.weight(.bold))
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
        }
    }
}

struct HermesLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HermesLiveActivityAttributes.self) { context in
            HermesLiveActivityView(state: context.state)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.status, systemImage: "waveform")
                        .foregroundStyle(.mint)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.updatedAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.response)
                        .font(.caption)
                        .lineLimit(2)
                }
            } compactLeading: {
                Image(systemName: "waveform")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text("H")
                    .font(.caption.weight(.bold))
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.mint)
            }
            .widgetURL(URL(string: "hermesvoice://activity"))
            .keylineTint(.mint)
        }
    }
}

struct HermesLiveActivityView: View {
    let state: HermesLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(state.status, systemImage: "waveform")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Spacer()
                Text(state.updatedAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(state.prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(state.response)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
        .padding()
        .foregroundStyle(.white)
    }
}

#Preview("Widget", as: .systemSmall) {
    HermesStatusWidget()
} timeline: {
    HermesStatusEntry(date: Date(), status: "Pronto", detail: "Chame pelo app ou Siri")
}

#Preview("Live Activity", as: .content, using: HermesLiveActivityAttributes.preview) {
    HermesLiveActivityWidget()
} contentStates: {
    HermesLiveActivityAttributes.ContentState.preview
}
