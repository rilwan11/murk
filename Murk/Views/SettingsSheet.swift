import SwiftUI
import MapKit
import UIKit

struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
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
                            AutoSkinCard(selected: state.autoSkin)
                                .onTapGesture { withAnimation { state.autoSkin = true } }
                            ForEach(Skin.allCases) { skin in
                                SkinCard(skin: skin, selected: !state.autoSkin && state.skin == skin)
                                    .onTapGesture { withAnimation { state.autoSkin = false; state.skin = skin } }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowBackground(Color.clear)
                } header: { header("Skins") }

                Section {
                    placeRow(icon: "location.fill",
                             title: state.currentPlace?.name ?? "Current Location",
                             subtitle: state.locationDenied ? "Location is off · enable in Settings" : "Follows you",
                             selected: state.isFollowingLocation) {
                        state.selectCurrentLocation()
                        dismiss()
                    }
                    ForEach(state.places) { place in
                        placeRow(icon: "mappin", title: place.name, subtitle: nil,
                                 selected: state.selectedID == place.id) {
                            state.select(place)
                            dismiss()
                        }
                    }
                    .onDelete { state.remove(at: $0) }

                    if adding {
                        TextField("Search for a city", text: $search.query)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        ForEach(search.results, id: \.self) { r in
                            Button {
                                Task {
                                    if let p = await search.resolve(r) {
                                        state.add(p)
                                        search.query = ""
                                        adding = false
                                        dismiss()
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
                            adding = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { searchFocused = true }
                        } label: {
                            Label("Add a city", systemImage: "plus.circle.fill")
                        }
                        .foregroundStyle(state.skin.accent)
                    }
                } header: { header("Locations") }

                Section {
                    Picker(selection: $state.unit) {
                        ForEach(TempUnit.allCases) { Text($0.symbol).tag($0) }
                    } label: { Label("Units", systemImage: "thermometer.medium") }
                    .pickerStyle(.segmented)
                    Toggle(isOn: $state.minimal) { Label("Minimal mode", systemImage: "eye.slash") }
                    Toggle(isOn: $state.alerts) { Label("Alerts & heads-up pill", systemImage: "exclamationmark.triangle") }
                    Toggle(isOn: $state.sound) { Label("Weather sounds", systemImage: "speaker.wave.2") }
                } header: { header("Settings") }
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
                        Text("Weather, but moodier.").foregroundStyle(.secondary)
                        Link("Forecast data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com")!)
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x0B0B0B))
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

struct SkinCard: View {
    let skin: Skin
    let selected: Bool
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
        .contentShape(Rectangle())
    }
}

struct AutoSkinCard: View {
    let selected: Bool
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
