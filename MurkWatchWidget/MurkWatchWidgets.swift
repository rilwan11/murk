import WidgetKit
import SwiftUI

struct WatchEntry: TimelineEntry {
    let date: Date
    let forecast: Forecast?
}

struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: .now, forecast: nil) }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        completion(WatchEntry(date: .now, forecast: WatchStore.cached()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        Task {
            let f = await WatchStore.current()
            let now = Date()
            // Every 15 minutes for the next hour, so "rain in 20 min" keeps counting down.
            let entries = (0..<4).map { WatchEntry(date: now.addingTimeInterval(Double($0) * 900), forecast: f) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(45 * 60))))
        }
    }
}

@main
struct MurkWatchWidgets: WidgetBundle {
    var body: some Widget {
        WatchRainComplication()
        WatchMoonComplication()
    }
}

struct WatchRainComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkWatchRain", provider: WatchProvider()) { e in
            WatchRainView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Murk Rain")
        .description("When rain starts or stops.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct WatchMoonComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkWatchMoon", provider: WatchProvider()) { e in
            WatchMoonView(entry: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Murk Moon")
        .description("Tonight's moon phase.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct WatchRainView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    var body: some View {
        if let f = entry.forecast {
            let v = Verdicts.rain(f, now: entry.date, unit: WatchStore.unit)
            let chance = f.hourly.first { $0.time.addingTimeInterval(3600) > entry.date }?.precipChance ?? 0
            switch family {
            case .accessoryInline:
                Label(v.line, systemImage: "cloud.rain.fill")
            case .accessoryCircular:
                Gauge(value: Double(chance), in: 0...100) { Image(systemName: "drop.fill") } currentValueLabel: { Text("\(chance)") }
                    .gaugeStyle(.accessoryCircular)
            case .accessoryCorner:
                Image(systemName: "cloud.rain.fill").font(.title3)
                    .widgetLabel { Text("\(chance)%") }
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Rain", systemImage: "cloud.rain.fill").font(.caption2.weight(.semibold)).widgetAccentable()
                    Text(v.big).font(.headline).lineLimit(1)
                    Text(v.line).font(.caption2).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Label("Open Murk", systemImage: "cloud.rain")
        }
    }
}

struct WatchMoonView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    var body: some View {
        let age = Astronomy.moonAge(entry.date)
        let lit = Int((Astronomy.illumination(age: age) * 100).rounded())
        let moon = Image(uiImage: MoonImage.image(age: age, points: 40, tint: UInt32(WatchInk.moon), scale: 2)).resizable()
        switch family {
        case .accessoryInline:
            Text("\(Astronomy.phaseName(age: age)), \(lit)%")
        case .accessoryCorner:
            moon.frame(width: 28, height: 28).widgetLabel { Text("\(lit)%") }
        case .accessoryRectangular:
            HStack(spacing: 8) {
                moon.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Astronomy.phaseName(age: age)).font(.headline).lineLimit(1)
                    if let f = entry.forecast {
                        Text(Verdicts.moon(f, now: entry.date).line).font(.caption2).lineLimit(2)
                    } else {
                        Text("\(lit)% lit").font(.caption2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            moon.padding(3)
        }
    }
}
