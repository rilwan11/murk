import Foundation

/// Sun and moon math, computed on-device.
enum Astronomy {
    static let synodicMonth = 29.530588853

    // MARK: Moon

    /// Days since the last new moon (0 … 29.53).
    static func moonAge(_ date: Date = Date()) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let a = (jd - 2451550.1).truncatingRemainder(dividingBy: synodicMonth)
        return a < 0 ? a + synodicMonth : a
    }

    /// Fraction of the disc lit (0 … 1).
    static func illumination(age: Double) -> Double {
        (1 - cos(2 * .pi * age / synodicMonth)) / 2
    }

    static func phaseName(age: Double) -> String {
        let names = ["New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
                     "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent", "New Moon"]
        return names[Int((age / synodicMonth * 8).rounded())]
    }

    /// Next date the moon reaches `targetAge` (0 = new, synodic/2 = full).
    static func next(targetAge: Double, from date: Date = Date()) -> Date {
        var d = (targetAge - moonAge(date)).truncatingRemainder(dividingBy: synodicMonth)
        if d < 0 { d += synodicMonth }
        if d < 0.5 { d += synodicMonth }
        return date.addingTimeInterval(d * 86400)
    }

    // MARK: Sun

    /// Sun altitude in degrees above the horizon.
    static func sunAltitude(latitude: Double, longitude: Double, at date: Date = Date()) -> Double {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n) * rad
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.0000004 * n) * rad
        let dec = asin(sin(eps) * sin(lambda))
        var ra = atan2(cos(eps) * sin(lambda), cos(lambda)) / rad
        if ra < 0 { ra += 360 }
        var eot = 4 * (L - ra)
        eot = eot.truncatingRemainder(dividingBy: 1440); if eot < 0 { eot += 1440 }
        if eot > 720 { eot -= 1440 }
        let utcMinutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86400) / 60
        let solarNoon = 720 - 4 * longitude - eot
        let h = (utcMinutes - solarNoon) / 4 * rad
        let phi = latitude * rad
        return asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h)) / rad
    }

    /// Sun direction in degrees: altitude above the horizon and azimuth clockwise from north.
    static func sunPosition(latitude: Double, longitude: Double, at date: Date = Date()) -> (altitude: Double, azimuth: Double) {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let L = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let g = (357.528 + 0.9856003 * n) * rad
        let lambda = (L + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad
        let eps = (23.439 - 0.0000004 * n) * rad
        let dec = asin(sin(eps) * sin(lambda))
        var ra = atan2(cos(eps) * sin(lambda), cos(lambda)) / rad
        if ra < 0 { ra += 360 }
        return horizontal(raDegrees: ra, dec: dec, latitude: latitude, longitude: longitude, date: date)
    }

    /// Converts a right ascension / declination to altitude and azimuth for a place and moment.
    static func horizontal(raDegrees: Double, dec: Double, latitude: Double, longitude: Double, date: Date) -> (altitude: Double, azimuth: Double) {
        let rad = Double.pi / 180
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        var gmst = (280.46061837 + 360.98564736629 * d).truncatingRemainder(dividingBy: 360)
        if gmst < 0 { gmst += 360 }
        let hDeg = gmst + longitude - raDegrees
        let h = hDeg * rad
        let phi = latitude * rad
        let alt = asin(sin(phi) * sin(dec) + cos(phi) * cos(dec) * cos(h))
        let azSouth = atan2(sin(h), cos(h) * sin(phi) - tan(dec) * cos(phi))   // from south, westward
        var az = azSouth / rad + 180
        az = az.truncatingRemainder(dividingBy: 360); if az < 0 { az += 360 }
        return (alt / rad, az)
    }

    // MARK: Moon position

    /// The moon's place in the sky (low-precision Meeus series, good to about a quarter of a degree),
    /// with altitude corrected for parallax so rise and set times are right.
    static func moonPosition(latitude: Double, longitude: Double, at date: Date = Date()) -> (altitude: Double, azimuth: Double, distanceKm: Double) {
        let rad = Double.pi / 180
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let L = 218.316 + 13.176396 * d
        let M = (134.963 + 13.064993 * d) * rad
        let F = (93.272 + 13.229350 * d) * rad
        let D = (297.850 + 12.190749 * d) * rad
        let Ms = (357.529 + 0.98560028 * d) * rad
        let lonTerms: Double = 6.289 * sin(M) + 1.274 * sin(2 * D - M) + 0.658 * sin(2 * D)
            + 0.214 * sin(2 * M) - 0.186 * sin(Ms) - 0.114 * sin(2 * F)
        let lambda = (L + lonTerms) * rad
        let latTerms: Double = 5.128 * sin(F) + 0.281 * sin(M + F) + 0.278 * sin(M - F) + 0.173 * sin(2 * D - F)
        let beta = latTerms * rad
        let dist: Double = 385001 - 20905 * cos(M) - 3699 * cos(2 * D - M) - 2956 * cos(2 * D)
        let eps = 23.439 * rad
        let ra = atan2(sin(lambda) * cos(eps) - tan(beta) * sin(eps), cos(lambda))
        let dec = asin(sin(beta) * cos(eps) + cos(beta) * sin(eps) * sin(lambda))
        var raDeg = ra / rad; if raDeg < 0 { raDeg += 360 }
        let p = horizontal(raDegrees: raDeg, dec: dec, latitude: latitude, longitude: longitude, date: date)
        let parallax = asin(6378.14 / dist) / rad
        return (p.altitude - parallax * cos(p.altitude * rad), p.azimuth, dist)
    }

    static func moonAltitude(latitude: Double, longitude: Double, at date: Date = Date()) -> Double {
        moonPosition(latitude: latitude, longitude: longitude, at: date).altitude
    }

    // MARK: Events

    /// When an altitude next crosses `threshold`, searched in 6-minute steps and interpolated.
    static func crossing(from start: Date, hours: Double = 24, threshold: Double, rising: Bool,
                         step: TimeInterval = 360, altitude: (Date) -> Double) -> Date? {
        var t = start
        var prev = altitude(start)
        let end = start.addingTimeInterval(hours * 3600)
        while t < end {
            let n = t.addingTimeInterval(step)
            let a = altitude(n)
            let crossed = rising ? (prev < threshold && a >= threshold) : (prev >= threshold && a < threshold)
            if crossed { return t.addingTimeInterval(step * (threshold - prev) / (a - prev)) }
            prev = a
            t = n
        }
        return nil
    }

    /// Sunrise/sunset altitude (refraction and the sun's radius), and the twilight edges.
    static let horizonAltitude = -0.833
    static let civil = -6.0, nautical = -12.0, astronomical = -18.0
    /// Golden hour: sun between 6° above and 4° below the horizon. Blue hour: 4° to 6° below.
    static let goldenTop = 6.0, blueTop = -4.0

    /// Hours of daylight on the local day containing `day` (0 in polar night, 24 in midnight sun).
    static func dayLength(latitude: Double, longitude: Double, day: Date, calendar: Calendar) -> Double {
        let start = calendar.startOfDay(for: day)
        let alt: (Date) -> Double = { sunPosition(latitude: latitude, longitude: longitude, at: $0).altitude }
        let rise = crossing(from: start, threshold: horizonAltitude, rising: true, step: 600, altitude: alt)
        let set = crossing(from: rise ?? start, threshold: horizonAltitude, rising: false, step: 600, altitude: alt)
        if let rise, let set { return set.timeIntervalSince(rise) / 3600 }
        return alt(start.addingTimeInterval(12 * 3600)) > horizonAltitude ? 24 : 0
    }

    /// Traditional names for the full moon by month.
    static func fullMoonName(_ date: Date, calendar: Calendar) -> String {
        let names = ["Wolf Moon", "Snow Moon", "Worm Moon", "Pink Moon", "Flower Moon", "Strawberry Moon",
                     "Buck Moon", "Sturgeon Moon", "Harvest Moon", "Hunter's Moon", "Beaver Moon", "Cold Moon"]
        let m = calendar.component(.month, from: date)
        return names[max(0, min(11, m - 1))]
    }
}
