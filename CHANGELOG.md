# Changelog

## Unreleased

### New
- **Reset on every page:** the round arrow in the corner of each 3D scene puts the view back and the slider back to now.
- **Tilt:** tilting the phone tilts the 3D scenes a little. Settings › Tilt scenes with the phone. Off with Reduce Motion.
- **Both units:** Settings › Also show °C (or °F) adds the other unit as a small chip on the Now page; tap it to switch.
- **Widgets show both units too** when that setting is on (under the big number, and on the Lock Screen widgets).
- **New widget style, "Light or dark, like the phone"** (free): a pale card in Light mode, near-black in Dark mode.
- **Smoother 3D:** scenes now draw at 60 fps (up to 120 Hz while you spin them) instead of 30.
- **Rain countdown on the Lock Screen and in the Dynamic Island** (Murk Pro): when rain is due to start or stop within the hour, a live timer and the next two hours as bars. Settings › Notify me about › Rain countdown.
- **Radar map** on the Rain page: the past two hours, looping. Tap it for a full-screen map with a time scrubber.
- **Apple Watch app:** Now, Rain and Moon pages, plus Rain and Moon complications.
- **Commute times** in Settings: the Rain page's commute check uses your own hours.
- Air page: wind direction is now a row of large arrows with compass letters under the chart.
- Sun page: no more "onChange tried to update multiple times per frame" warning.
- CI draws every widget and fails if one comes out blank.

### Reliability
- **Sound:** fixed a data race between the screen and the audio thread. Sound now recovers on its own when headphones or Bluetooth connect or disconnect.
- **Widget taps:** tapping any widget opens Murk on the Now page. `murk://now`, `air`, `rain`, `sun`, `moon` and `settings` are supported; anything else is ignored.
- **Switching cities quickly:** a slow answer for a city you've already left can no longer show its weather, its error or a stuck spinner.
- **Location:** finding you now gives up after 10 seconds and falls back to a saved city, saying so. No more endless spinner.
- **Regions that write decimals with a comma:** weather requests are always built correctly.
- **Alerts:** the same alert is never notified twice, in the app or in the background.

### Behavior changes
- **Location is asked for only when you choose "Use Current Location".** If you had already allowed it, nothing changes.
- **Notifications are asked for only when you turn one on** in Settings › Notify me about. The old "Alerts" switch now controls just the heads-up pill.
- **The Now page says how fresh the forecast is:** updated, refreshing, saved forecast, offline, or forecast service unavailable, with tap to retry. A saved forecast stays on screen instead of an error.
- **Coordinates sent to weather services are rounded to about 1 km** (previously about 10 m). A new **Approximate location** switch rounds to about 11 km.
- **Widgets show the app's last forecast** instead of fetching their own, so they match the app and work offline.
- **Times follow your 12- or 24-hour setting.**
- Tagline is now "Weather with Atmosphere."

### New
- **Murk Pro** (monthly or annual): unlimited saved cities, the Aurora, Storm and Sunset skins plus Auto, and notifications for rain, wind, UV and air quality. The free app keeps the full forecast, Current Location and one saved city, widgets and official alerts. Cities you already saved are kept.
- **More in Murk Pro:** all your places at a glance (each under its own sky, with local time and how far ahead or behind it is); widgets you can point at any saved city; two extra widget styles (Skin color and Midnight); Aurora, Storm and Sunset app icons.
- **iCloud sync** for saved cities and preferences is written and tested but switched off in this build, because it needs the paid Apple Developer Program. See `docs/APP_STORE.md`, section 7.
- Widgets are now editable (long-press › Edit Widget). Existing widgets keep following the app.
- Alert details sheet, with severe alerts marked by shape as well as color.
- "What changes next" line under the conditions (rain starting or easing, strong gusts, a big temperature swing).
- Hourly wind chart on the Air page.
- Reorder saved cities.
- VoiceOver descriptions for the scene, forecast, hour slider, pages and widgets; Reduce Motion and Reduce Transparency are respected; text follows your text-size setting up to a limit.

### Battery
- The 3D scene stops drawing when it's off screen or the app is in the background, and runs at 30 fps unless it's raining or you're spinning it.
- Widget artwork is drawn off the main thread.

### Under the hood
- `WeatherRepository` data layer with a provider configuration, retry policy and versioned, bounded, hashed disk cache.
- Unit tests, UI smoke tests, and a pull-request CI workflow.
