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
2. Confirm the terms for NWS alerts (US government data) and for anything added later (radar, historical).
3. Supply the key at build time: set the `MURK_WEATHER_API_KEY` build setting (for example in an untracked `.xcconfig`). With a key, Murk uses the commercial hosts automatically; without one it uses the free endpoint. Do not commit the key. A key shipped inside an app can be extracted, so use a plan with usage caps or put a proxy in front of it.
4. Watch usage and cost: `WeatherRepository.onEvent` reports each request's kind, success and duration (no coordinates) and is the place to attach monitoring.

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
> **Murk Pro paywall:** Settings › "Murk Pro". It also appears when you (a) tap "Add a city" with one city already saved, (b) tap the Aurora, Storm, Sunset or Auto skin, or (c) turn on a rain, wind, air-quality or UV notification. Restore Purchases and Manage Subscription are on the paywall and in Settings › Murk Pro.
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
- [ ] Purchases exercised end to end (needs the StoreKit configuration in Xcode or a sandbox account; not run on CI)
- [ ] Tested on a physical iPhone after these changes

Owner actions before submission:

- [ ] Enroll in the paid Apple Developer Program
- [ ] Commercial weather-data plan and API key (section 3)
- [ ] Create the subscription group and both products (section 2)
- [ ] Host the Privacy Policy and Terms at their final URLs (the GitHub links work today)
- [ ] Screenshots, App Privacy answers (section 4), review notes (section 5)
- [ ] Manual pass: fresh install with no permissions; add first and second city as a free user; monthly and annual sandbox purchase; trial start, cancel, expiry, restore; widget tap; VoiceOver and largest text size; Reduce Motion and Reduce Transparency; network loss during purchase and during refresh; launch after renewal and after expiry

Not built yet (do not advertise): iCloud sync, per-location widgets, alternate app icons and widget styles, travel mode / multi-location overview, Live Activities, historical forecasts.
