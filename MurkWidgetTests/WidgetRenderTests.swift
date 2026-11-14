import XCTest
import SwiftUI
import WidgetKit

/// Draws every widget from a sample forecast and fails if it comes out blank,
/// so a widget that renders nothing can't ship.
@MainActor
final class WidgetRenderTests: XCTestCase {
    private func forecast(rainFromHour: Int? = 1) -> Forecast {
        let data = DebugStubs.openMeteoJSON(now: Date(), rainFromHour: rainFromHour)
        return try! WeatherAPI.parseForecast(data, place: .sanDiego, fetchedAt: Date(), isCached: false)
    }

    private func entry(_ f: Forecast?) -> WeatherEntry {
        WeatherEntry(date: Date(), forecast: f, unit: .celsius, skin: .graphite, reason: f == nil ? "No forecast yet" : nil)
    }

    /// Share of pixels that aren't transparent, and how many distinct colors there are.
    private func ink<V: View>(_ view: V, size: CGSize = CGSize(width: 170, height: 170)) -> (coverage: Double, colors: Int) {
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.black))
        r.scale = 1
        guard let cg = r.cgImage else { return (0, 0) }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var lit = 0
        var seen = Set<UInt32>()
        for i in stride(from: 0, to: px.count, by: 4) {
            let (r, g, b) = (px[i], px[i + 1], px[i + 2])
            if Int(r) + Int(g) + Int(b) > 60 { lit += 1 }
            seen.insert(UInt32(r >> 4) << 8 | UInt32(g >> 4) << 4 | UInt32(b >> 4))
        }
        return (Double(lit) / Double(w * h), seen.count)
    }

    private func assertDrawn<V: View>(_ view: V, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let (coverage, colors) = ink(view)
        XCTAssertGreaterThan(coverage, 0.02, "\(name) drew almost nothing (\(coverage))", file: file, line: line)
        XCTAssertGreaterThan(colors, 3, "\(name) is a flat fill", file: file, line: line)
    }

    func testMainWidgetDrawsTheForecast() {
        assertDrawn(WidgetView(entry: entry(forecast())), "Weather widget")
    }

    func testPageWidgetsDraw() {
        let e = entry(forecast())
        let f = e.forecast!
        assertDrawn(PageWidgetFrame(entry: e, link: "murk://rain") { RainWidgetView(f: $0, u: e.unit, now: e.date) }, "Rain widget")
        assertDrawn(PageWidgetFrame(entry: e, link: "murk://air") { AirWidgetView(f: $0, u: e.unit, now: e.date) }, "Air widget")
        assertDrawn(PageWidgetFrame(entry: e, link: "murk://sun") { DaylightWidgetView(f: $0, now: e.date) }, "Daylight widget")
        assertDrawn(PageWidgetFrame(entry: e, link: "murk://moon") { MoonWidgetView(f: $0, now: e.date, skin: e.skin) }, "Moon widget")
        XCTAssertFalse(f.hourly.isEmpty)
    }

    func testEmptyWidgetStillSaysSomething() {
        assertDrawn(WidgetView(entry: entry(nil)), "Empty widget")
    }

    func testRainCountdownDraws() throws {
        let f = forecast(rainFromHour: 0)
        let now = Date()
        let plan = RainCountdown(kind: .starts, at: now.addingTimeInterval(1200),
                                 bars: [0, 0, 0.4, 1.2, 2.5, 1, 0.3, 0], from: now, snow: false)
        let (coverage, _) = ink(RainLockScreen(place: f.place.name, state: plan, stale: false), size: CGSize(width: 360, height: 120))
        XCTAssertGreaterThan(coverage, 0.02)
    }

    func testCountdownPlan() {
        let now = Date()
        var f = forecast(rainFromHour: nil)
        f.current.precipitation = 0
        f.minutely = (0..<8).map { MinutePoint(time: now.addingTimeInterval(Double($0) * 900), precip: $0 >= 2 ? 1 : 0) }
        let starts = RainCountdown.plan(f, now: now)
        XCTAssertEqual(starts?.kind, .starts)
        XCTAssertEqual(starts?.at.timeIntervalSince1970 ?? 0, now.addingTimeInterval(1800).timeIntervalSince1970, accuracy: 1)

        f.minutely = (0..<8).map { MinutePoint(time: now.addingTimeInterval(Double($0) * 900), precip: $0 < 3 ? 1 : 0) }
        XCTAssertEqual(RainCountdown.plan(f, now: now)?.kind, .stops)

        f.minutely = (0..<8).map { MinutePoint(time: now.addingTimeInterval(Double($0) * 900), precip: $0 >= 6 ? 1 : 0) }
        XCTAssertNil(RainCountdown.plan(f, now: now), "rain 90 minutes out is too far for a countdown")

        f.minutely = (0..<8).map { MinutePoint(time: now.addingTimeInterval(Double($0) * 900), precip: 0) }
        XCTAssertNil(RainCountdown.plan(f, now: now))
    }
}
