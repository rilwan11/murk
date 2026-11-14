# Murk: Weather with Atmosphere

*Weather with Atmosphere.* A 3D weather app for iPhone, built with SwiftUI and SceneKit.

Docs: [Privacy Policy](PRIVACY.md) · [Terms of Use](TERMS.md) · [Changelog](CHANGELOG.md) · [App Store readiness](docs/APP_STORE.md)

- **3D Now screen.** The cloud, the sun or moon, and the temperature are real 3D objects. Drag to spin them in any direction (it rotates all the way over the top and underneath), pinch to zoom, tap to grow a new cloud, and tap ↺ to reset the view.
- **Live weather** from [Open-Meteo](https://open-meteo.com). It's free and needs no API key or account.
- **Your location** via GPS, plus **city search** to save and switch places.
- **Five pages.** Swipe left from the lower part of the screen, or tap the dots:
  - **Now:** 3D scene and 8-day strip. Tap a day to preview it in 3D.
  - **Air:** wind, gusts, direction, humidity, pressure, visibility, AQI, UV, and a wind chart.
  - **Rain:** chance and amount by day, plus the next 24 hours.
  - **Sun:** sunrise, sunset, solar noon, daylight, and the sun's current height.
  - **Moon:** tonight's real phase, illumination, and the next full and new moons.
- **Settings:** skins (Graphite, Ember, Aurora), °F/°C, minimal mode, a heads-up pill, and weekly stats.
- **Widgets:** small, medium (5-day), and large (7-day with temperature bars) for the home screen, plus circular, rectangular, and inline lock-screen widgets. They follow the city you last viewed in the app, along with your units and skin, and refresh about every 30 minutes.
- **App icon:** "Night Murk", a matte black cloud with a crescent moon.

## What you need

- A Mac with **Xcode 15 or newer**
- An iPhone on **iOS 17 or newer**
- An Apple ID. A free one works for installing on your own phone, but the app expires after 7 days and you re-run it from Xcode. A paid Developer account ($99/yr) removes that limit and lets you use TestFlight or the App Store.

## Set it up (option A: XcodeGen, fastest)

```bash
brew install xcodegen
cd Murk
xcodegen
open Murk.xcodeproj
```

## Before you build: App Group (needed for widgets)

The app tells the widget which city to show through an App Group called `group.com.rilwan11.murk`. When you change the bundle ID (see below), change the group to match, e.g. `group.com.yourname.murk`, in three places:
`Shared/SharedStore.swift`, `project.yml`, and both `.entitlements` files. Then run `xcodegen` again.
If your Apple account can't create App Groups, the widgets still work but always show San Diego in °F.

## Set it up (option B: plain Xcode)

1. In Xcode, choose **File → New → Project → iOS App**. Name it `Murk`, set Interface to SwiftUI, and Language to Swift.
2. Delete the `ContentView.swift` and `MurkApp.swift` that Xcode created.
3. Drag this repo's `Murk/` folder (Models, Services, Scene, Store, Theme, Views, MurkApp.swift) into the project and tick **Copy items if needed**.
4. Select the target and open the **Info** tab. Add **Privacy – Location When In Use Usage Description** with the text *"Murk uses your location to show the weather where you are."*
5. Under **General**, set the Minimum Deployment to iOS 17, and drag `Shared/` into the project too (app target).
6. Add `Assets.xcassets` (from `Murk/`) to the app target. It holds the app icon.
7. Widgets: choose **File → New → Target → Widget Extension** and name it `MurkWidget` (untick Live Activity and Configuration Intent). Replace its generated Swift files with `MurkWidget/MurkWidget.swift`. Then tick the **MurkWidget** target membership for `Shared/*`, `Models/Weather.swift`, `Theme/Skin.swift`, `Services/WeatherService.swift`, and `Services/Astronomy.swift`.
8. In **Signing & Capabilities**, add the **App Groups** capability to *both* targets with the same group ID.

## Run it on your iPhone

1. Plug in your iPhone (or pair it over Wi-Fi) and pick it as the run destination.
2. Under **Signing & Capabilities**, choose your Team (your Apple ID). If Xcode complains about the bundle ID, change `com.rilwan11.murk` to something unique, like `com.yourname.murk`.
3. Press **Run** (⌘R).
4. On the phone, the first time only, go to **Settings → General → VPN & Device Management**, trust your developer profile, and turn on **Developer Mode** if iOS asks.

## A heads-up

This code was written without a Mac, so it has **never been compiled**. Expect a few small compile errors to fix. If Xcode shows errors, paste them to Claude and they'll be quick to sort out.

## Project layout

```
Murk/
  MurkApp.swift              app entry, refresh on foreground
  Models/Weather.swift       places, units, WMO condition codes, forecast types
  Services/WeatherService    Open-Meteo forecast + air quality
  Services/LocationServices  GPS (CoreLocation) + city search (MapKit)
  Services/Astronomy         moon phase + sun height, computed on device
  Store/AppState.swift       saved places, settings, loading
  Scene/WeatherSceneView     SceneKit 3D scene (clouds, 3D digits, sun/moon, rain/snow)
  Theme/Skin.swift           skins and colors
  Views/                     Root pager, Now, Air/Rain/Sun/Moon, Settings
  Assets.xcassets            app icon
Shared/                      code used by both the app and the widget
MurkWidget/                  home + lock screen widgets (WidgetKit)
```

Weather data by Open-Meteo.com (CC BY 4.0).
