import SwiftUI
import MapKit

struct SettingsSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var search = CitySearch()
    @State private var adding = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Skin.allCases) { skin in
                                SkinCard(skin: skin, selected: state.skin == skin)
                                    .onTapGesture { withAnimation { state.skin = skin } }
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
                    Toggle(isOn: $state.alerts) { Label("Heads-up pill", systemImage: "exclamationmark.triangle") }
                } header: { header("Settings") }
                .tint(state.skin.accent)

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
