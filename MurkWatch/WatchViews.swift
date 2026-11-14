import SwiftUI

struct WatchRoot: View {
    @EnvironmentObject var model: WatchModel

    var body: some View {
        if let f = model.forecast {
            TabView {
                WatchNow(f: f).tag(0)
                WatchRain(f: f).tag(1)
                WatchMoon(f: f).tag(2)
            }
            .tabViewStyle(.verticalPage)
        } else if let problem = model.problem {
            VStack(spacing: 8) {
                Image(systemName: "icloud.slash").font(.title2)
                Text(problem).multilineTextAlignment(.center).font(.footnote)
                Button("Try again") { Task { await model.refresh(force: true) } }
            }
        } else {
            ProgressView()
        }
    }
}

private extension Color {
    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct WatchNow: View {
    @EnvironmentObject var model: WatchModel
    let f: Forecast

    var body: some View {
        let u = model.unit
        let c = f.current
        VStack(alignment: .leading, spacing: 2) {
            Label(f.place.name, systemImage: f.place.isCurrentLocation ? "location.fill" : "mappin")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(u.temp(c.temperature))°").font(.system(size: 56, weight: .black, design: .rounded))
                Image(systemName: c.condition.symbol).symbolRenderingMode(.multicolor).font(.title2)
            }
            Text(c.condition.title).font(.headline)
            if let d = f.daily.first {
                Text("H \(u.temp(d.high))°  L \(u.temp(d.low))°").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(updated).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color(hex: 0x1C2333).gradient, for: .tabView)
        .accessibilityElement(children: .combine)
    }

    private var updated: String {
        let mins = Int(Date().timeIntervalSince(f.fetchedAt) / 60)
        return mins < 2 ? String(localized: "Just updated") : String(localized: "Updated \(f.fetchedAt.formatted(date: .omitted, time: .shortened))")
    }
}

struct WatchRain: View {
    @EnvironmentObject var model: WatchModel
    let f: Forecast

    var body: some View {
        let v = Verdicts.rain(f, now: Date(), unit: model.unit)
        let hours = Array(f.hourly.filter { $0.time.addingTimeInterval(3600) > Date() }.prefix(12))
        VStack(alignment: .leading, spacing: 6) {
            Label("Rain", systemImage: "cloud.rain.fill").font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: WatchInk.rain))
            Text(v.big).font(.system(size: 34, weight: .black, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(v.line).font(.footnote).lineLimit(3)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours) { h in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: WatchInk.rain).opacity(h.precipChance >= 30 ? 1 : 0.35))
                        .frame(height: max(2, 34 * CGFloat(h.precipChance) / 100))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 34, alignment: .bottom)
            .accessibilityHidden(true)
            Text("Next 12 hours, chance").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color(hex: 0x14243A).gradient, for: .tabView)
    }
}

struct WatchMoon: View {
    let f: Forecast

    var body: some View {
        let age = Astronomy.moonAge(Date())
        let v = Verdicts.moon(f, now: Date())
        VStack(spacing: 6) {
            Image(uiImage: MoonImage.image(age: age, points: 84, tint: UInt32(WatchInk.moon), scale: 2))
                .resizable().frame(width: 84, height: 84)
                .accessibilityHidden(true)
            Text(Astronomy.phaseName(age: age)).font(.headline)
            Text(v.line).font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary).lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color(hex: 0x0B0E1A).gradient, for: .tabView)
        .accessibilityElement(children: .combine)
    }
}
