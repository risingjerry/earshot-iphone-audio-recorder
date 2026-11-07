import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct EarshotWidgets: WidgetBundle {
    var body: some Widget { RecordingLiveActivity() }
}

/// Lock screen and Dynamic Island while the microphone records a conversation: elapsed time and a stop button.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivity.self) { ctx in
            HStack(spacing: 12) {
                Image(systemName: ctx.attributes.symbol).foregroundStyle(.red).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earshot \(ctx.attributes.title)").font(.subheadline.weight(.semibold))
                    elapsed(ctx.attributes.startedAt).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                stopButton
            }
            .padding(16)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(ctx.attributes.title, systemImage: ctx.attributes.symbol).foregroundStyle(.red).font(.subheadline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(ctx.attributes.startedAt).font(.subheadline)
                }
                DynamicIslandExpandedRegion(.bottom) { stopButton }
            } compactLeading: {
                Image(systemName: ctx.attributes.symbol).foregroundStyle(.red)
            } compactTrailing: {
                elapsed(ctx.attributes.startedAt).frame(maxWidth: 52).font(.caption2)
            } minimal: {
                Image(systemName: ctx.attributes.symbol).foregroundStyle(.red)
            }
        }
    }

    private func elapsed(_ since: Date) -> some View {
        Text(timerInterval: since...Date.distantFuture, countsDown: false).monospacedDigit()
    }

    private var stopButton: some View {
        Button(intent: StopRecordingIntent()) {
            Label("停止", systemImage: "stop.fill")
        }
        .tint(.red)
    }
}
