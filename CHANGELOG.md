# Changelog

## Unreleased

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
