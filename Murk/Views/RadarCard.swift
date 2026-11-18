import SwiftUI
import MapKit

/// The past two hours of radar around the place, looping. Tap for a full-screen map you can move.
struct RadarCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Environment(\.pageActive) private var active
    let place: Place
    @State private var catalog: RadarService.Catalog?
    @State private var failed = false
    @State private var index = 0
    @State private var full = false
    /// Nothing loads until the Rain page is first shown, so radar tiles never compete with the forecast.
    @State private var started = false

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: String(localized: "Radar"), trailing: frameLabel)
            ZStack {
                if started, let catalog, !catalog.frames.isEmpty {
                    RadarMap(place: place, catalog: catalog, index: index, interactive: false)
                        .allowsHitTesting(false)
                } else {
                    Rectangle().fill(p.ink.opacity(0.06))
                    Text(failed ? String(localized: "Radar isn't available right now.") : String(localized: "Loading radar…"))
                        .font(.footnote).foregroundStyle(p.muted)
                }
            }
            .frame(height: 210)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture { if catalog?.frames.isEmpty == false { full = true } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Rain radar for the past two hours around \(place.name)"))
            .accessibilityHint(Text("Opens a larger map"))
            .accessibilityAddTraits(.isButton)
            RadarCredit(palette: p).padding(.horizontal, 16)
        }
        .onChange(of: active, initial: true) { _, on in if on { started = true } }
        .task(id: "\(place.id)-\(started)") { if started { await load() } }
        .task(id: "\(active)-\(catalog?.frames.count ?? 0)") { await loop() }
        .fullScreenCover(isPresented: $full) {
            if let catalog { RadarFullScreen(place: place, catalog: catalog) }
        }
    }

    private var frameLabel: String? {
        guard let f = catalog?.frames, f.indices.contains(index) else { return String(localized: "past 2 hours") }
        return f[index].time.formatted(date: .omitted, time: .shortened)
    }

    private func load() async {
        do {
            let c = try await RadarService.catalog()
            catalog = c
            index = max(0, c.frames.count - 1)
            failed = false
        } catch {
            failed = catalog == nil
        }
    }

    /// Plays the frames while the page is on screen, resting on the newest one.
    private func loop() async {
        guard active, let n = catalog?.frames.count, n > 1 else { return }
        while !Task.isCancelled {
            let last = index == n - 1
            try? await Task.sleep(for: .milliseconds(last ? 1600 : 450))
            guard !Task.isCancelled else { return }
            index = (index + 1) % n
        }
    }
}

struct RadarCredit: View {
    let palette: Palette
    var body: some View {
        Link(destination: RadarService.credit) {
            Text("Weather data by RainViewer").font(.mono(9)).underline()
        }
        .foregroundStyle(palette.muted)
    }
}

/// Map with one tile overlay per frame; only the current frame is visible, so changing frames is instant.
struct RadarMap: UIViewRepresentable {
    let place: Place
    let catalog: RadarService.Catalog
    let index: Int
    var interactive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.showsCompass = false
        // Radar tiles are coarse: keep the view regional.
        map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 60_000, maxCenterCoordinateDistance: 4_000_000)
        context.coordinator.center(on: place, map: map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.center(on: place, map: map)
        context.coordinator.show(catalog, index: index, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var catalog: RadarService.Catalog?
        private var overlays: [RadarTileOverlay] = []
        private var renderers: [String: MKTileOverlayRenderer] = [:]
        private var current = -1
        private var placeID: String?
        private let pin = MKPointAnnotation()

        /// Follows the place the app is showing, not just the one the map first opened on.
        func center(on place: Place, map: MKMapView) {
            guard place.id != placeID || pin.coordinate.latitude != place.latitude else { return }
            let first = placeID == nil
            placeID = place.id
            let c = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
            pin.coordinate = c
            pin.title = place.name
            if map.annotations.isEmpty { map.addAnnotation(pin) }
            map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 260_000, longitudinalMeters: 260_000), animated: !first)
        }

        func show(_ c: RadarService.Catalog, index: Int, on map: MKMapView) {
            if c != catalog {
                map.removeOverlays(overlays)
                renderers = [:]
                overlays = c.frames.map { RadarTileOverlay(host: c.host, frame: $0) }
                catalog = c
                current = -1
                map.addOverlays(overlays, level: .aboveRoads)
            }
            guard index != current else { return }
            current = index
            for (i, o) in overlays.enumerated() {
                guard let r = renderers[o.frame.path] else { continue }
                r.alpha = i == index ? 0.75 : 0
                r.setNeedsDisplay()
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let o = overlay as? RadarTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKTileOverlayRenderer(tileOverlay: o)
            r.alpha = overlays.firstIndex(of: o) == current ? 0.75 : 0
            renderers[o.frame.path] = r
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "place")
            v.markerTintColor = .white
            v.glyphImage = UIImage(systemName: "mappin")
            v.titleVisibility = .hidden
            return v
        }
    }
}

/// The radar map you can pan and pinch, with a scrubber for the frames.
struct RadarFullScreen: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let place: Place
    let catalog: RadarService.Catalog
    @State private var index: Double = 0
    @State private var playing = true

    private func ago(_ i: Int) -> String {
        guard catalog.frames.indices.contains(i), let last = catalog.frames.last else { return "" }
        if i == catalog.frames.count - 1 { return String(localized: "Latest") }
        let mins = Int(last.time.timeIntervalSince(catalog.frames[i].time) / 60)
        return String(localized: "\(mins) min earlier")
    }

    var body: some View {
        let n = catalog.frames.count
        let i = min(max(0, Int(index.rounded())), max(0, n - 1))
        ZStack(alignment: .bottom) {
            RadarMap(place: place, catalog: catalog, index: i, interactive: true).ignoresSafeArea()
            VStack(spacing: 10) {
                HStack {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(playing ? Text("Pause") : Text("Play"))
                    Text(catalog.frames.indices.contains(i) ? catalog.frames[i].time.formatted(date: .omitted, time: .shortened) : "")
                        .font(.mono(15, .bold)).monospacedDigit()
                    Spacer()
                    Text(ago(i))
                        .font(.mono(11)).foregroundStyle(.secondary)
                }
                if n > 1 {
                    Slider(value: $index, in: 0...Double(n - 1), step: 1, onEditingChanged: { _ in playing = false })
                        .tint(.white)
                        .accessibilityLabel(Text("Radar time"))
                }
                HStack {
                    RadarCredit(palette: .onGlass)
                    Spacer()
                    Text("Past 2 hours, every 10 minutes").font(.mono(9)).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(Text("Close"))
            .padding(16)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { index = Double(max(0, n - 1)) }
        .task(id: playing) {
            guard playing, n > 1 else { return }
            while !Task.isCancelled {
                let last = Int(index.rounded()) >= n - 1
                try? await Task.sleep(for: .milliseconds(last ? 1600 : 450))
                guard !Task.isCancelled, playing else { return }
                index = last ? 0 : index + 1
            }
        }
    }
}
