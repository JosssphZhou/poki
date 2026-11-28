import SwiftUI
import WidgetKit

@main
struct PokiWatchFace: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PokiWatchFace", provider: PokiWatchFaceTimeline()) { _ in
            PokiWatchFaceEntry()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Poki")
        .description("Open Poki to record a task.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

private struct PokiWatchFaceEntry: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryRectangular:
            Label("Poki", systemImage: "waveform")
                .accessibilityLabel("Open Poki")
        default:
            Image(systemName: "waveform")
                .font(.title2.weight(.semibold))
                .accessibilityLabel("Open Poki")
        }
    }
}

private struct PokiWatchFaceTimeline: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }

    func placeholder(in context: Context) -> Entry { Entry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [placeholder(in: context)], policy: .never))
    }
}
