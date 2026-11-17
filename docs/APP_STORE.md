# Murk: Weather with Atmosphere — App Store readiness

Nothing here has been submitted. Items marked **OWNER** need a decision or an account action from the product owner.

## 1. Metadata

| Field | Value |
| --- | --- |
| App name | Murk: Weather with Atmosphere |
| Subtitle | 3D forecasts, widgets and alerts |
| Tagline | Weather with Atmosphere. |
| Home Screen name | Murk |
| Category | Weather |
| Privacy Policy URL | https://github.com/rilwan11/murk/blob/main/PRIVACY.md |
| Terms of Use (EULA) URL | https://github.com/rilwan11/murk/blob/main/TERMS.md |
| Support URL | https://github.com/rilwan11/murk/issues |
| Marketing URL | **OWNER** (optional) |
| Keywords | weather,forecast,widget,rain,wind,moon,sun,uv,air quality,alerts,3d |

**Description**

> Murk: Weather with Atmosphere turns the forecast into a 3D scene you can spin: clouds, sun, moon and the temperature, lit for the time of day.
>
> FREE
> • Current conditions and an 8-day forecast
> • Five pages: Now, Air, Rain, Sun and Moon
> • Your current location and one saved city
> • Home Screen and Lock Screen widgets
> • Official US weather alerts
> • Works offline with the last forecast
>
> MURK PRO (subscription)
> • Unlimited saved cities
> • Aurora, Storm and Sunset skins, plus Auto
> • Notifications for rain, wind, UV and air quality
> • All your places at a glance, with local times
> • Widgets for any saved city, plus extra widget styles
> • Aurora, Storm and Sunset app icons
>
> No account. No ads. No tracking.
>
> Murk Pro is an auto-renewing subscription, monthly or annual. Payment is charged to your Apple ID. It renews automatically unless canceled at least 24 hours before the end of the period. Manage or cancel in Settings › Apple ID › Subscriptions.
>
> Forecast and air-quality data by Open-Meteo. US alerts by the National Weather Service.
> Privacy: (URL above) · Terms: (URL above)

Wording to keep out of metadata and screenshots: "accurate", "real-time", "severe-weather protection", or any promise about alert timing. Alerts are checked when the app refreshes.

Screenshots must be real captures of the app and widgets. Any screenshot showing a Pro skin or a second city needs a "Requires Murk Pro" caption.

## 2. In-app purchases (App Store Connect) — **OWNER**

Requires the paid Apple Developer Program. One subscription group, **Murk Pro**:

| Product ID | Period | Price | Offer |
| --- | --- | --- | --- |
| `com.rilwan11.murk.pro.monthly` | 1 month | $2.99 | — |
| `com.rilwan11.murk.pro.annual` | 1 year | $19.99 | Introductory: 7-day free trial |

Optional launch promotion: an offer code for the annual plan ("Founding Member"). No lifetime product.
Submit both products with the app version that first contains the paywall.

## 3. Weather data licensing — **OWNER, blocks release of Murk Pro**

Open-Meteo's free endpoint is for non-commercial use. Before Murk Pro is sold:

1. Buy an Open-Meteo commercial plan (or license another provider) and confirm it covers forecast and air quality for a paid app.
2. Confirm the terms for NWS alerts (US government data) and for anything added later (historical).
3. **Radar (RainViewer):** the free Weather Maps API is for personal and educational use, needs the visible credit "Weather data by RainViewer" linking to rainviewer.com (shown under the map), and since January 2026 gives only the past 2 hours, zoom 7 and one color scheme. A paid app needs RainViewer's commercial terms (arranged case by case) or another radar source. A different source plugs in by changing `RadarService.catalog()` and `tileURL`.
4. Supply the key at build time: set the `MURK_WEATHER_API_KEY` build setting (for example in an untracked `.xcconfig`). With a key, Murk uses the commercial hosts automatically; without one it uses the free endpoint. Do not commit the key. A key shipped inside an app can be extracted, so use a plan with usage caps or put a proxy in front of it.
5. Watch usage and cost: `WeatherRepository.onEvent` reports each request's kind, success and duration (no coordinates) and is the place to attach monitoring.

A different provider plugs in by adding a `ProviderConfig` and, if its response format differs, a parser next to `WeatherAPI.parseForecast`.

## 4. App Privacy answers (App Store Connect)

Based on what the code does today. Re-check before every release.

| Data type | Collected? | Linked to identity | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| Coarse Location | Yes (sent to weather providers, rounded to ~1 km or ~11 km) | No | No | App Functionality |
| Precise Location | No (coordinates are rounded before leaving the device) — **OWNER: confirm you agree 1 km rounding counts as coarse; if in doubt, declare Precise** | No | No | App Functionality |
| Purchases | Handled by Apple; Murk stores only an on-device flag. Declare "Purchase History" only if a server or analytics is added. | — | — | — |
| Identifiers, Usage Data, Diagnostics, Contact Info | No | — | — | — |

No third-party SDKs. No ATT prompt (nothing is tracked). The app and widget each ship a `PrivacyInfo.xcprivacy`.

## 5. App Review notes (template)

> Murk needs no account or login.
>
> **Location:** Murk does not ask for location at launch. Tap "USE MY LOCATION" on the main screen, or Settings (slider icon) › "Use Current Location". If you decline, the app keeps working with a saved city (San Diego by default) and city search.
>
> **Murk Pro paywall:** Settings › "Murk Pro". It also appears when you (a) tap "Add a city" with one city already saved, (b) tap the Aurora, Storm, Sunset or Auto skin, (c) turn on a rain, wind, air-quality or UV notification, (d) tap "All places at a glance", or (e) tap a tinted app icon. Restore Purchases and Manage Subscription are on the paywall and in Settings › Murk Pro.
>
> **Testing Pro:** use a sandbox Apple ID. Products: com.rilwan11.murk.pro.monthly and com.rilwan11.murk.pro.annual (7-day trial).
>
> **Notifications:** permission is requested only after turning on a switch under Settings › "Notify me about", following an explanation.
>
> **Offline:** with no connection Murk shows the last saved forecast and an "OFFLINE" status line with tap to retry. Widgets show the same saved forecast.
>
> **Data sources:** forecast and air quality from Open-Meteo (commercial plan); US alerts from the National Weather Service. Attribution is in Settings.

## 6. Release checklist

Code (done in this repository, verified by CI unless noted):

- [x] Audio data race, widget deep links, stale loads, location timeout, locale-safe coordinates, alert de-duplication
- [x] App and widgets work offline from a saved forecast
- [x] StoreKit 2 entitlements, paywall with prices from StoreKit, billing period, trial terms, auto-renewal wording, Restore, Manage, Privacy and Terms links
- [x] No external purchase links; no account required
- [x] Paywall appears only at value moments or from Settings; the forecast is never blocked
- [x] Location requested only on "Use Current Location", When In Use only; notification permission only when an alert is turned on
- [x] Privacy policy, Terms of Use, privacy manifests
- [x] Unit tests and CI
- [x] Pro features: all places at a glance, widgets for a chosen city, widget styles, tinted app icons (unit tested; not yet tried on a device)
- [x] Rain countdown Live Activity (Lock Screen and Dynamic Island), Murk Pro, starts only while Murk is open and rain changes within the hour
- [x] Radar map on the Rain page (past 2 hours), with RainViewer credit
- [x] Apple Watch app (Now, Rain, Moon) and Rain and Moon complications, standalone (scheme MurkWatch)
- [x] Widget render tests: every widget is drawn from a sample forecast on CI and the build fails if one is blank
- [ ] iCloud sync switched on and tested on two devices (section 7)
- [ ] Purchases exercised end to end (needs the StoreKit configuration in Xcode or a sandbox account; not run on CI)
- [ ] Tested on a physical iPhone after these changes

Owner actions before submission:

- [ ] Enroll in the paid Apple Developer Program
- [ ] Commercial weather-data plan and API key (section 3)
- [ ] Create the subscription group and both products (section 2)
- [ ] Host the Privacy Policy and Terms at their final URLs (the GitHub links work today)
- [ ] Screenshots, App Privacy answers (section 4), review notes (section 5)
- [ ] Manual pass: fresh install with no permissions; add first and second city as a free user; monthly and annual sandbox purchase; trial start, cancel, expiry, restore; widget tap; VoiceOver and largest text size; Reduce Motion and Reduce Transparency; network loss during purchase and during refresh; launch after renewal and after expiry

Built but switched off in this build: **iCloud sync** (see section 7). Do not advertise it until it is on and tested on two devices.

Not built (do not advertise): historical forecasts, future (nowcast) radar.

Live Activity limits to state in marketing: the countdown starts when Murk is open; background refreshes keep it current when iOS runs them, but there is no push server, so it can lag.

## 9. Apple Watch

The watch app is a separate, watch-only app (`WKWatchOnly`), bundle ID `com.rilwan11.murk.watch`. Run it from Xcode with the **MurkWatch** scheme and your watch as the destination. It is not embedded in the iPhone app, so installing Murk on the iPhone doesn't install it on the watch. To ship it alongside the iPhone app later, embed `MurkWatch` in the `Murk` target and set `WKCompanionAppBundleIdentifier` to `com.rilwan11.murk`.

## 7. Turning on iCloud sync — **OWNER**

The code is in the app (`Murk/Pro/CloudSync.swift`, unit tested against a stand-in store) but hidden, because the iCloud entitlement can't be signed with a free Apple account.

1. Enroll in the paid Apple Developer Program.
2. In `project.yml`, set `MURK_ICLOUD_SYNC: "YES"` and add to the Murk target's entitlements: `com.apple.developer.ubiquity-kvstore-identifier: $(TeamIdentifierPrefix)$(CFBundleIdentifier)`.
3. Run `xcodegen`, build to two devices signed in to the same Apple ID, and check: turn sync on on both, add a city on one, see it on the other; "Reset synced data" removes it.
4. Add "iCloud sync" to the paywall list (`PaywallView.rows`), the description above and the privacy answers (no change: data stays in the user's private iCloud).

What syncs: saved cities, units, skin, minimal mode, heads-up pill, sounds, notification thresholds. What never syncs: current location, the selected city, notification on/off switches, any history.

## 8. Widgets for a chosen city and widget styles

Long-press a Murk widget › Edit Widget. "Place" lists the saved cities and "Style" offers Murk glass (default), Light or dark, Skin color and Midnight. City and non-default styles apply only with Murk Pro; without it the widget follows the app in Murk glass or Light or dark. Existing widgets keep working and follow the app.
