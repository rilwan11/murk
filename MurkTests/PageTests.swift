import XCTest
@testable import Murk

private func plain(_ s: String) -> String { s.replacingOccurrences(of: "\u{202F}", with: " ") }

final class SunAndMoonTests: XCTestCase {
    private let ny = (lat: 40.7128, lon: -74.0060, tz: TimeZone(identifier: "America/New_York")!)

    /// Published (USNO) New York times for 1 Jan 2025: sunrise 7:20, sunset 16:39.
    func testSunriseAndSunsetMatchPublishedTimes() {
        let day = Fixture.date(2025, 1, 1, 12, zone: "America/New_York")
        let d = Verdicts.sunDay(latitude: ny.lat, longitude: ny.lon, day: day, timeZone: ny.tz)
        let cal = Calendar.zoned(ny.tz)
        func minutes(_ x: Date?) -> Int { guard let x else { return -1 }; return cal.component(.hour, from: x) * 60 + cal.component(.minute, from: x) }
        XCTAssertEqual(Double(minutes(d.sunrise)), 7 * 60 + 20, accuracy: 3)
        XCTAssertEqual(Double(minutes(d.sunset)), 16 * 60 + 39, accuracy: 3)
    }

    func testTwilightComesInOrder() throws {
        let d = Verdicts.sunDay(latitude: 34.05, longitude: -118.24, day: Fixture.date(2026, 6, 10), timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let order = [d.astroDawn, d.nauticalDawn, d.civilDawn, d.sunrise, d.goldenMorningEnd, d.goldenEveningStart, d.sunset, d.civilDusk, d.nauticalDusk, d.astroDusk]
        let times = try order.map { try XCTUnwrap($0) }
        XCTAssertEqual(times, times.sorted())
    }

    func testDayLength() {
        let london = Calendar.zoned(TimeZone(identifier: "Europe/London")!)
        let june = Astronomy.dayLength(latitude: 51.5074, longitude: -0.1278, day: Fixture.date(2026, 6, 21, 12, zone: "Europe/London"), calendar: london)
        let december = Astronomy.dayLength(latitude: 51.5074, longitude: -0.1278, day: Fixture.date(2026, 12, 21, 12, zone: "Europe/London"), calendar: london)
        XCTAssertEqual(june, 16 + 38.0 / 60, accuracy: 0.15)
        XCTAssertEqual(december, 7 + 50.0 / 60, accuracy: 0.15)
        let quito = Astronomy.dayLength(latitude: -0.18, longitude: -78.47, day: Fixture.date(2026, 3, 1, 12, zone: "America/Guayaquil"),
                                        calendar: Calendar.zoned(TimeZone(identifier: "America/Guayaquil")!))
        XCTAssertEqual(quito, 12.1, accuracy: 0.15)
    }

    func testSunDirection() {
        // Northern summer noon: high in the south. Morning: in the east.
        let noon = Astronomy.sunPosition(latitude: 34.05, longitude: -118.24, at: Fixture.date(2026, 6, 21, 13))
        XCTAssertGreaterThan(noon.altitude, 75)
        let morning = Astronomy.sunPosition(latitude: 34.05, longitude: -118.24, at: Fixture.date(2026, 6, 21, 8))
        XCTAssertEqual(morning.azimuth, 80, accuracy: 20)
    }

    /// A full moon rises around sunset; a new moon rises around sunrise. Checked in three cities.
    func testMoonRisesOppositeTheSunWhenFull() {
        let full = Astronomy.next(targetAge: Astronomy.synodicMonth / 2, from: Fixture.date(2026, 6, 1, 0, zone: "UTC"))
        for (lat, lon, zone) in [(40.71, -74.01, "America/New_York"), (51.51, -0.13, "Europe/London"), (-33.87, 151.21, "Australia/Sydney")] {
            let tz = TimeZone(identifier: zone)!
            let sun = Verdicts.sunDay(latitude: lat, longitude: lon, day: full, timeZone: tz)
            guard let set = sun.sunset else { return XCTFail("no sunset in \(zone)") }
            let rise = Astronomy.crossing(from: set.addingTimeInterval(-4 * 3600), hours: 8, threshold: 0.125, rising: true) {
                Astronomy.moonAltitude(latitude: lat, longitude: lon, at: $0)
            }
            guard let rise else { return XCTFail("no moonrise near sunset in \(zone)") }
            XCTAssertLessThan(abs(rise.timeIntervalSince(set)), 2.5 * 3600, zone)
        }
    }

    func testMoonAltitudeIsContinuousAndSane() {
        var prev: Double?
        for i in 0..<48 {
            let a = Astronomy.moonAltitude(latitude: 32.7, longitude: -117.2, at: Fixture.date(2026, 11, 14, 0).addingTimeInterval(Double(i) * 1800))
            XCTAssertTrue((-90...90).contains(a))
            if let prev { XCTAssertLessThan(abs(a - prev), 10) }
            prev = a
        }
    }

    func testFullMoonNames() {
        let cal = Calendar.zoned(TimeZone(identifier: "UTC")!)
        XCTAssertEqual(Astronomy.fullMoonName(Fixture.date(2026, 12, 24, 12, zone: "UTC"), calendar: cal), "Cold Moon")
        XCTAssertEqual(Astronomy.fullMoonName(Fixture.date(2026, 10, 26, 12, zone: "UTC"), calendar: cal), "Hunter's Moon")
    }
}

final class VerdictTests: XCTestCase {
    private let morning = Fixture.date(2026, 6, 10, 8)

    func testRainStartTimeIsTheHeadline() {
        let f = Fixture.forecast(Fixture.la, now: morning, rainFromHour: 15)
        let v = Verdicts.rain(f, now: morning, unit: .fahrenheit)
        XCTAssertEqual(plain(v.big), "3 PM")
        XCTAssertTrue(plain(v.line).hasPrefix("Rain starts around 3 PM"), v.line)
        XCTAssertTrue(v.line.contains("in"), "mentions the amount")
    }

    func testRainTomorrowSaysTomorrow() {
        let f = Fixture.forecast(Fixture.la, now: morning, rainFromHour: 30)
        let v = Verdicts.rain(f, now: morning, unit: .celsius)
        XCTAssertTrue(plain(v.line).contains("tomorrow around 6 AM"), v.line)
    }

    func testDryDay() {
        let f = Fixture.forecast(Fixture.la, now: morning)
        XCTAssertEqual(Verdicts.rain(f, now: morning, unit: .fahrenheit).big, "Dry")
    }

    func testCommuteCheck() {
        let f = Fixture.forecast(Fixture.la, now: morning, rainFromHour: 17)
        let rows = Verdicts.commute(f, now: morning)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].1, "Dry")
        XCTAssertEqual(rows[1].1, "Umbrella, 80%")
    }

    func testWindVerdict() {
        let f = Fixture.forecast(Fixture.la, now: morning)
        let v = Verdicts.wind(f, at: nil, now: morning, unit: .fahrenheit)
        XCTAssertEqual(v.big, "7")
        XCTAssertEqual(v.unit, "mph W")
        XCTAssertTrue(v.line.contains("no strong gusts"), v.line)
        XCTAssertEqual(Verdicts.windWord(2), "Calm")
        XCTAssertEqual(Verdicts.windWord(40), "Windy")
    }

    func testDewPointWords() {
        XCTAssertEqual(Verdicts.dewWord(5), "Dry")
        XCTAssertEqual(Verdicts.dewWord(12), "Comfortable")
        XCTAssertEqual(Verdicts.dewWord(22), "Sticky")
    }

    func testPressureTrend() {
        let now = morning
        let falling = [HourlyPoint(time: now.addingTimeInterval(-3 * 3600), temperature: 10, precipChance: 0, pressure: 1016),
                       HourlyPoint(time: now, temperature: 10, precipChance: 0, pressure: 1012)]
        XCTAssertEqual(Verdicts.pressureTrend(falling, now: now), .falling)
        let steady = [HourlyPoint(time: now.addingTimeInterval(-3 * 3600), temperature: 10, precipChance: 0, pressure: 1012),
                      HourlyPoint(time: now, temperature: 10, precipChance: 0, pressure: 1012.4)]
        XCTAssertEqual(Verdicts.pressureTrend(steady, now: now), .steady)
    }

    func testUVAdvice() {
        let f = Fixture.forecast(Fixture.la, now: morning)
        XCTAssertEqual(plain(Verdicts.uvAdvice(f, now: morning)), "Sunscreen from 10 AM to 3 PM")
    }

    func testSunVerdictDuringTheDay() {
        let f = Fixture.forecast(Fixture.la, now: morning)
        let v = Verdicts.sun(f, now: morning)
        XCTAssertEqual(v.unit, "of daylight left")
        XCTAssertTrue(v.line.hasPrefix("Sunset at"))
    }

    func testAirParsing() throws {
        let json = """
        {"timezone":"America/Los_Angeles","current":{"us_aqi":72.4,"pm2_5":22.0,"pm10":30.0,"ozone":60.0,"nitrogen_dioxide":10.0,"grass_pollen":null},
         "hourly":{"time":["2026-06-10T08:00","2026-06-10T09:00"],"us_aqi":[70,null]}}
        """
        let a = try WeatherAPI.parseAir(Data(json.utf8))
        XCTAssertEqual(a.aqi, 72)
        XCTAssertEqual(a.hourly.count, 1)
        XCTAssertEqual(a.mainPollutant, "PM2.5")
        XCTAssertTrue(a.pollen.isEmpty)
        XCTAssertEqual(Verdicts.aqiWord(72), "Moderate")
    }

    func testForecastAsksForTheNewHourlyFields() {
        let q = WeatherAPI.forecastURL(Fixture.la, config: .openMeteoFree).query ?? ""
        for field in ["dew_point_2m", "pressure_msl", "cloud_cover", "snowfall", "relative_humidity_2m"] {
            XCTAssertTrue(q.contains(field), field)
        }
        XCTAssertTrue((WeatherAPI.airQualityURL(Fixture.la, config: .openMeteoFree).query ?? "").contains("hourly=us_aqi"))
    }
}

final class RainNowTests: XCTestCase {
    func testRainDueThisHourIsNow() {
        let now = Fixture.date(2026, 6, 10, 13).addingTimeInterval(24 * 60)     // 1:24 PM
        let f = Fixture.forecast(Fixture.la, now: now, rainFromHour: 13)
        let v = Verdicts.rain(f, now: now, unit: .fahrenheit)
        XCTAssertEqual(v.big, "Now")
        XCTAssertTrue(v.line.hasPrefix("Rain possible this hour"), v.line)
    }
}

final class RadarTests: XCTestCase {
    func testParsesFramesOldestFirst() throws {
        let json = #"{"version":"2.0","generated":1,"host":"https://tilecache.rainviewer.com","radar":{"past":[{"time":1700000600,"path":"/v2/radar/b"},{"time":1700000000,"path":"/v2/radar/a"}],"nowcast":[]}}"#
        let c = try RadarService.parse(Data(json.utf8))
        XCTAssertEqual(c.host, "https://tilecache.rainviewer.com")
        XCTAssertEqual(c.frames.map(\.path), ["/v2/radar/a", "/v2/radar/b"])
        XCTAssertEqual(RadarService.tileURL(host: c.host, path: "/v2/radar/a", z: 5, x: 3, y: 9)?.absoluteString,
                       "https://tilecache.rainviewer.com/v2/radar/a/256/5/3/9/2/1_1.png")
    }

    func testCloseTilesAreCutFromZoomSeven() {
        let s = RadarService.source(z: 9, x: 87, y: 205)
        XCTAssertEqual(s.z, 7); XCTAssertEqual(s.x, 21); XCTAssertEqual(s.y, 51)
        XCTAssertEqual(s.rect.minX, 0.75, accuracy: 1e-9)
        XCTAssertEqual(s.rect.minY, 0.25, accuracy: 1e-9)
        XCTAssertEqual(s.rect.width, 0.25, accuracy: 1e-9)
        let same = RadarService.source(z: 6, x: 10, y: 20)
        XCTAssertEqual(same.z, 6); XCTAssertEqual(same.x, 10); XCTAssertEqual(same.rect.width, 1)
    }

    func testCommuteWindowsFollowSettings() {
        let c = CommuteTimes(morning: 7, evening: 18)
        XCTAssertEqual(c.windows.map { [$0.0, $0.1] }, [[7, 8], [18, 19]])
        let d = Fixture.defaults()
        c.save(d)
        XCTAssertEqual(CommuteTimes.load(d), c)
    }
}
