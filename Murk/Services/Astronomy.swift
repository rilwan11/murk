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
}
