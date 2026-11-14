import SwiftUI

/// Loads every saved place at once, without touching what the main screen is doing.
@MainActor
final class OverviewModel: ObservableObject {
    @Published private(set) var forecasts: [String: Forecast] = [:]
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var isLoading = false

    func load(_ places: [Place], repository: WeatherProviding, onLoaded: @escaping (Forecast) -> Void = { _ in }) async {
        isLoading = true
        defer { isLoading = false }
        // Saved forecasts first, so the list is never empty while it refreshes.
        for p in places where forecasts[p.id] == nil {
            if let c = repository.cached(for: p) { forecasts[p.id] = c }
        }
        await withTaskGroup(of: (String, Forecast?).self) { group in
            for p in places {
                group.addTask { (p.id, try? await repository.core(for: p)) }
            }
            for await (id, f) in group {
                if let f {
                    forecasts[id] = f
                    failed.remove(id)
                    onLoaded(f)
                } else {
                    failed.insert(id)
                }
            }
        }
    }
}

/// Murk Pro: all your places at a glance, each under its own sky, with the local time —
/// for trips, and for people you keep an eye on elsewhere.
struct PlacesOverview: View {
    @EnvironmentObject var state: AppState
    @StateObject private var model = OverviewModel()
    /// Called after a place is chosen, so the caller can close.
    var onPick: () -> Void = {}

    private var places: [Place] {
        var list: [Place] = []
        if state.isFollowingLocation, let here = state.currentPlace { list.append(here) }
        return list + state.places
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(places) { place in
                    Button {
                        if place.isCurrentLocation { state.selectCurrentLocation() } else { state.select(place) }
                        onPick()
                    } label: {
                        PlaceCard(place: place, forecast: model.forecasts[place.id], failed: model.failed.contains(place.id),
                                  unit: state.unit)
                    }
                    .buttonStyle(.plain)
                }
                Text("Tap a place to open it. Times are local to each place.")
                    .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(hex: 0x0B0B0B).ignoresSafeArea())
        .navigationTitle("All places")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if model.isLoading { ToolbarItem(placement: .topBarTrailing) { ProgressView() } } }
        .refreshable { await reload() }
        .task { await reload() }
    }

    private func reload() async {
        let unit = state.unit, skin = state.skin
        await model.load(places, repository: state.repository) { f in
            // Widgets pinned to this city get the fresh forecast too.
            guard !f.place.isCurrentLocation else { return }
            WidgetSnapshot(forecast: f, unit: unit, skin: skin).save(to: WidgetSnapshot.url(placeID: f.place.id))
        }
    }
}

private struct PlaceCard: View {
    let place: Place
    let forecast: Forecast?
    let failed: Bool
    let unit: TempUnit

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            // Every card wears the sky over that place right now, whatever skin the app is in.
            let sky = forecast.flatMap { Sky.current($0, skin: .graphite, at: tl.date) } ?? Sky.at(altitude: -30, cover: 0.9, precip: false)
            let p = Palette(skin: .graphite, sky: sky)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        if place.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: 12, weight: .bold)) }
                        Text(place.name).font(.system(size: 20, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    if let f = forecast {
                        Text(Self.clock(tl.date, f.timeZone) + " · " + Self.offsetText(f.timeZone, at: tl.date))
                            .font(.mono(10)).tracking(1).foregroundStyle(p.muted)
                        Text(f.current.condition.title).font(.system(size: 14, weight: .semibold))
                        if f.isCached || f.isStale(now: tl.date) {
                            Text("SAVED \(Outlook.age(f.age(now: tl.date)))").font(.mono(9)).tracking(1).foregroundStyle(p.muted)
                        }
                    } else {
                        Text(failed ? "Couldn't load. Pull down to retry." : "Loading…").font(.footnote).foregroundStyle(p.muted)
                    }
                }
                Spacer(minLength: 8)
                if let f = forecast {
                    Image(systemName: f.current.condition.symbol).symbolRenderingMode(.multicolor).font(.system(size: 26))
                        .accessibilityHidden(true)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(unit.temp(f.current.temperature))°").font(.system(size: 40, weight: .black).width(.compressed))
                        if let d = f.daily.first {
                            Text("H \(unit.temp(d.high))°  L \(unit.temp(d.low))°").font(.mono(10)).foregroundStyle(p.muted)
                        }
                    }
                }
            }
            .foregroundStyle(p.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .background(
                LinearGradient(stops: [.init(color: Color(hex: sky.top), location: 0), .init(color: Color(hex: sky.mid), location: 0.55),
                                       .init(color: Color(hex: sky.bottom), location: 1)], startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text("Opens this place"))
        }
    }

    static func clock(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone
        return date.formatted(style).uppercased()
    }

    /// "SAME TIME AS YOU", "3 HR AHEAD", "5.5 HR BEHIND".
    static func offsetText(_ zone: TimeZone, at date: Date, home: TimeZone = .current) -> String {
        let diff = Double(zone.secondsFromGMT(for: date) - home.secondsFromGMT(for: date)) / 3600
        if abs(diff) < 0.01 { return String(localized: "SAME TIME AS YOU") }
        let n = abs(diff)
        let hours = n == n.rounded() ? String(Int(n)) : String(format: "%.1f", locale: Locale.current, n)
        return diff > 0 ? String(localized: "\(hours) HR AHEAD") : String(localized: "\(hours) HR BEHIND")
    }
}

enum PlacesOverviewText {
    static func offset(_ zone: TimeZone, at date: Date, home: TimeZone) -> String { PlaceCard.offsetText(zone, at: date, home: home) }
}
