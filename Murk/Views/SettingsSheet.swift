import SwiftUI
import MapKit
import UIKit

struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: EntitlementStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var explainNotifications = false
    @State private var notificationsBlocked = false
    @State private var pendingRule: ((inout NotificationRules) -> Void)?
    @State private var manageSubscription = false
    @StateObject private var search = CitySearch()
    @State private var adding = false
    @FocusState private var searchFocused: Bool
    @State private var wallpaperNote: String?
    @State private var makingWallpaper = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Skin.allCases.sorted { !$0.isPremium && $1.isPremium }) { skin in
                                let on = !state.autoSkin && state.skin == skin
                                SkinCard(skin: skin, selected: on, locked: skin.isPremium && !state.isPro)
                                    .onTapGesture { withAnimation { state.choose(skin) } }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(Text(skin.isPremium && !state.isPro ? "\(skin.name) skin, Murk Pro" : "\(skin.name) skin"))
                                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                            }
                            AutoSkinCard(selected: state.autoSkin, locked: !state.isPro)
                                .onTapGesture { withAnimation { state.choose(nil) } }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text(state.isPro ? "Auto skin, follows the weather" : "Auto skin, Murk Pro"))
                                .accessibilityAddTraits(state.autoSkin ? [.isButton, .isSelected] : .isButton)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: { header("Skins") }

                Section {
                    // Current Location: says plainly whether it's in use, off, blocked, or standing in with a saved city.
                    if state.useLocation {
                        placeRow(icon: state.isFollowingLocation ? "location.fill" : "location.slash",
                                 title: state.isFollowingLocation ? (state.currentPlace?.name ?? String(localized: "Current Location")) : String(localized: "Current Location"),
                                 subtitle: locationSubtitle,
                                 selected: state.isFollowingLocation) {
                            state.selectCurrentLocation()
                            dismiss()
                        }
                        if state.locationDenied {
                            Button("Open Settings to allow location") {
                                if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                            }
                            .font(.footnote)
                        }
                    } else {
                        Button {
                            state.selectCurrentLocation()
                            dismiss()
                        } label: {
                            Label("Use Current Location", systemImage: "location")
                        }
                        .foregroundStyle(state.skin.accent)
                    }
                    ForEach(state.places) { place in
                        placeRow(icon: "mappin", title: place.name,
                                 subtitle: state.fallbackPlace?.id == place.id ? String(localized: "Showing this while your location isn't available") : nil,
                                 selected: state.selectedID == place.id || state.fallbackPlace?.id == place.id) {
                            state.select(place)
                            dismiss()
                        }
                    }
                    .onDelete { state.remove(at: $0) }
                    .onMove { state.move(from: $0, to: $1) }

                    if adding {
                        TextField("Search for a city", text: $search.query)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        ForEach(search.results, id: \.self) { r in
                            Button {
                                Task {
                                    if let p = await search.resolve(r) {
                                        search.query = ""
                                        adding = false
                                        if state.add(p) { dismiss() }
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title).foregroundStyle(.primary)
                                    if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    } else {
                        Button {
                            // A second saved city is where Murk Pro starts.
                            guard state.canAddPlace else { state.paywall = .city; return }
                            adding = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true }
                        } label: {
                            Label(state.canAddPlace ? "Add a city" : "Add a city · Murk Pro", systemImage: "plus.circle.fill")
                        }
                        .foregroundStyle(state.skin.accent)
                    }
                    if state.useLocation {
                        Button("Stop using my location") { state.stopUsingLocation() }.font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { header("Locations") } footer: {
                    Text("Murk asks for your location only when you choose Use Current Location, and only while the app is open. Saved cities always work without it.")
                }

                Section {
                    Picker(selection: $state.unit) {
                        ForEach(TempUnit.allCases) { Text($0.symbol).tag($0) }
                    } label: { Label("Units", systemImage: "thermometer.medium") }
                    .pickerStyle(.segmented)
                    Toggle(isOn: $state.minimal) { Label("Minimal mode", systemImage: "eye.slash") }
                    Toggle(isOn: $state.alerts) { Label("Heads-up pill", systemImage: "exclamationmark.triangle") }
                    Toggle(isOn: $state.sound) { Label("Weather sounds", systemImage: "speaker.wave.2") }
                    Toggle(isOn: $state.approximateLocation) { Label("Approximate location", systemImage: "scope") }
                } header: { header("Settings") } footer: {
                    Text("Approximate location rounds your coordinates to about 11 km (7 mi) before they are sent to the weather services. Forecasts stay close; alerts near a county line may be missed.")
                }
                .tint(state.skin.accent)

                Section {
                    ruleToggle("Official weather alerts", "exclamationmark.triangle.fill", pro: false, isOn: state.rules.official) { $0.official = $1 }
                    ruleToggle("Rain on the way", "cloud.rain.fill", pro: true, isOn: state.rules.rain) { $0.rain = $1 }
                    if state.rules.rain && state.isPro {
                        Stepper("At \(state.rules.rainChance)% chance or more", value: $state.rules.rainChance, in: 30...90, step: 10).font(.footnote)
                    }
                    ruleToggle("Strong gusts", "wind", pro: true, isOn: state.rules.wind) { $0.wind = $1 }
                    if state.rules.wind && state.isPro {
                        Stepper("At \(state.unit.wind(state.rules.gustKmh).lowercased()) or more", value: $state.rules.gustKmh, in: 30...110, step: 10).font(.footnote)
                    }
                    ruleToggle("Poor air quality", "aqi.medium", pro: true, isOn: state.rules.aqi) { $0.aqi = $1 }
                    if state.rules.aqi && state.isPro {
                        Stepper("At AQI \(state.rules.aqiLevel) or more", value: $state.rules.aqiLevel, in: 51...201, step: 50).font(.footnote)
                    }
                    ruleToggle("High UV", "sun.max.trianglebadge.exclamationmark", pro: true, isOn: state.rules.uv) { $0.uv = $1 }
                    if state.rules.uv && state.isPro {
                        Stepper("At UV \(Int(state.rules.uvLevel)) or more", value: $state.rules.uvLevel, in: 3...11, step: 1).font(.footnote)
                    }
                    if notificationsBlocked {
                        Button("Notifications are off for Murk. Open Settings to allow them.") {
                            if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                        }
                        .font(.footnote)
                    }
                } header: { header("Notify me about") } footer: {
                    Text("Notifications are for the place Murk is showing. They are checked when Murk refreshes, including in the background when iOS allows, so they can arrive late. Official alerts come from the US National Weather Service.")
                }
                .tint(state.skin.accent)

                Section {
                    Button { state.paywall = .general } label: {
                        HStack {
                            Label(state.isPro ? "Murk Pro is active" : "Murk Pro", systemImage: state.isPro ? "checkmark.seal.fill" : "sparkles")
                            Spacer()
                            if !state.isPro { Text("See what's included").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                    Button("Manage Subscription") { manageSubscription = true }
                    if let m = store.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    #if DEBUG
                    Toggle("Debug: unlock Pro (test builds only)", isOn: Binding(get: { store.debugUnlock }, set: { store.debugUnlock = $0 }))
                    #endif
                } header: { header("Murk Pro") }
                .tint(state.skin.accent)

                Section {
                    Button {
                        makeWallpaper()
                    } label: {
                        HStack {
                            Label("Save weather wallpaper", systemImage: "photo.on.rectangle.angled")
                            Spacer()
                            if makingWallpaper { ProgressView() }
                        }
                    }
                    .disabled(state.forecast == nil || makingWallpaper)
                    if let wallpaperNote {
                        Text(wallpaperNote).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { header("Wallpaper") } footer: {
                    Text("Renders today's 3D weather as a lock-screen wallpaper and saves it to Photos. Set it from Photos → Share → Use as Wallpaper.")
                }

                if let f = state.forecast, !f.daily.isEmpty {
                    let hot = f.daily.max { $0.high < $1.high }!
                    let cold = f.daily.min { $0.low < $1.low }!
                    let wet = f.daily.max { $0.precipChance < $1.precipChance }!
                    Section {
                        stat("flame.fill", "Hottest", "\(state.unit.temp(hot.high))° \(label(hot, f))")
                        stat("snowflake", "Coolest", "\(state.unit.temp(cold.low))° \(label(cold, f))")
                        stat("umbrella.fill", "Wettest", "\(wet.precipChance)% \(label(wet, f))")
                    } header: { header("This week · \(f.place.name)") }
                }

                Section {
                    VStack(spacing: 6) {
                        Text("Murk").font(.display(22))
                        Text("Weather with Atmosphere.").foregroundStyle(.secondary)
                        if let st = state.status() { Text(st.text.capitalized).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        Link("Forecast and air quality by Open-Meteo.com", destination: URL(string: ProviderConfig.current.attributionURL)!)
                            .font(.footnote)
                        Link("US alerts by the National Weather Service", destination: URL(string: "https://www.weather.gov")!)
                            .font(.footnote)
                        HStack(spacing: 18) {
                            Link("Privacy Policy", destination: Legal.privacy)
                            Link("Terms of Use", destination: Legal.terms)
                            Link("Support", destination: Legal.support)
                        }
                        .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background {
                // A dimmed copy of the current sky, so settings feel like part of the same place.
                ZStack {
                    Color(hex: 0x0B0B0B)
                    if let f = state.forecast, let sky = Sky.current(f, skin: state.skin) {
                        SkyBackground(sky: sky).opacity(0.45)
                    }
                }
                .ignoresSafeArea()
            }
            .alert("Turn on notifications?", isPresented: $explainNotifications) {
                Button("Allow notifications") { Task { await finishEnablingRule(ask: true) } }
                Button("Not now", role: .cancel) { pendingRule = nil }
            } message: {
                Text("Murk will only notify you about the weather you choose here, for the place it is showing. iOS will ask for permission next. You can change this any time.")
            }
            .manageSubscriptionsSheet(isPresented: $manageSubscription)
            .sheet(item: $state.paywall) { reason in
                PaywallView(reason: reason).environmentObject(store)
            }
            .navigationTitle("Murk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                        .buttonStyle(.bordered).clipShape(Circle())
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !state.places.isEmpty { EditButton() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var locationSubtitle: String {
        if state.isFollowingLocation { return String(localized: "Follows you while Murk is open") }
        let fallback = state.places.first.map { String(localized: " · showing \($0.name)") } ?? ""
        switch state.locationProblem {
        case .denied: return String(localized: "Location is off for Murk") + fallback
        case .timedOut: return String(localized: "Couldn't find you in time") + fallback
        case .unavailable: return String(localized: "Location isn't available") + fallback
        case nil: return state.selectedID == nil ? String(localized: "Finding you…") : String(localized: "Tap to show where you are")
        }
    }

    /// A notification switch. Pro rules open the paywall; turning one on explains, then asks iOS for permission once.
    private func ruleToggle(_ title: LocalizedStringKey, _ icon: String, pro: Bool, isOn: Bool,
                            _ set: @escaping (inout NotificationRules, Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { isOn && (!pro || state.isPro) }, set: { on in
            if !on { var r = state.rules; set(&r, false); state.rules = r; return }
            if pro && !state.isPro { state.paywall = .alerts; return }
            pendingRule = { set(&$0, true) }
            Task {
                if await Notifier.isAuthorized() { await finishEnablingRule(ask: false) }
                else if await Notifier.isDenied() { pendingRule = nil; notificationsBlocked = true }
                else { explainNotifications = true }
            }
        })) {
            HStack {
                Label(title, systemImage: icon)
                if pro && !state.isPro { Text("PRO").font(.mono(9)).padding(.horizontal, 5).padding(.vertical, 2).overlay(Capsule().stroke(.secondary)) }
            }
        }
    }

    private func finishEnablingRule(ask: Bool) async {
        guard let apply = pendingRule else { return }
        pendingRule = nil
        let allowed = ask ? await Notifier.request() : true
        if allowed {
            var r = state.rules; apply(&r); state.rules = r
            notificationsBlocked = false
        } else {
            notificationsBlocked = true
        }
    }

    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.mono(12)).tracking(2).foregroundStyle(.secondary)
    }

    private func placeRow(icon: String, title: String, subtitle: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(.blue).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(state.skin.accent).fontWeight(.bold) }
            }
        }
    }

    private func stat(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func makeWallpaper() {
        guard let f = state.forecast else { return }
        makingWallpaper = true
        let c = f.current.condition
        let alt = Astronomy.sunAltitude(latitude: f.place.latitude, longitude: f.place.longitude)
        let config = SceneConfig(temperature: String(state.unit.temp(f.current.temperature)), cover: c.cloudCover,
                                 precip: .none, intensity: 0, isDay: f.current.isDay || alt > -2,
                                 moonAge: Astronomy.moonAge(), skin: state.skin,
                                 windSpeed: 0, windDirection: 0, thunder: false, sunAltitude: (alt / 2).rounded() * 2)
        let px = UIScreen.main.nativeBounds.size
        DispatchQueue.main.async {
            let image = WeatherScene().wallpaper(config, size: CGSize(width: px.width, height: px.height))
            makingWallpaper = false
            guard let image else { wallpaperNote = "Couldn't render the wallpaper."; return }
            WallpaperSaver.shared.save(image) { ok in
                wallpaperNote = ok ? "Saved to Photos. Open it and tap Share → Use as Wallpaper."
                                   : "Couldn't save. Allow Murk to add photos in Settings → Privacy → Photos."
            }
        }
    }

    private func label(_ d: DailyWeather, _ f: Forecast) -> String {
        let i = f.daily.firstIndex { $0.date == d.date } ?? 0
        return i == 0 ? "Today" : state.dayLabel(d, index: i).capitalized
    }
}

/// "PRO" marker with a lock, for looks that need Murk Pro.
struct ProBadge: View {
    var body: some View {
        Label("PRO", systemImage: "lock.fill").font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55))).foregroundStyle(.white)
            .padding(8)
    }
}

struct SkinCard: View {
    let skin: Skin
    let selected: Bool
    var locked = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22).fill(skin.swatch)
            RoundedRectangle(cornerRadius: 20)
                .fill(skin.gem)
                .frame(width: 66, height: 66)
                .rotationEffect(.degrees(30))
                .shadow(color: skin == .aurora ? Color(hex: 0x7D6BFF) : .clear, radius: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -18)
            Text(skin.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(skin.swatchText)
                .padding(14)
        }
        .frame(width: 124, height: 150)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Color.white : .clear, lineWidth: 3))
        .overlay(alignment: .topTrailing) {
            if locked { ProBadge() } else if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(8) }
        }
        .contentShape(Rectangle())
    }
}

struct AutoSkinCard: View {
    let selected: Bool
    var locked = false
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Color(hex: 0xF5B445), Color(hex: 0x6B2D6E), Color(hex: 0x0F1A24)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "wand.and.stars").font(.system(size: 40, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity).offset(y: -18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto").font(.system(size: 17, weight: .heavy))
                Text("Follows the weather").font(.system(size: 10, weight: .medium)).opacity(0.8)
            }
            .foregroundStyle(.white).padding(14)
        }
        .frame(width: 124, height: 150)
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Color.white : .clear, lineWidth: 3))
        .overlay(alignment: .topTrailing) {
            if locked { ProBadge() } else if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(8) }
        }
        .contentShape(Rectangle())
    }
}

/// Bridges UIImageWriteToSavedPhotosAlbum's target/selector callback to a closure.
final class WallpaperSaver: NSObject {
    static let shared = WallpaperSaver()
    private var done: ((Bool) -> Void)?
    func save(_ image: UIImage, done: @escaping (Bool) -> Void) {
        self.done = done
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(finished(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    @objc private func finished(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        let cb = done; done = nil
        DispatchQueue.main.async { cb?(error == nil) }
    }
}
