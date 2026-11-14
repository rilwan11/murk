# Murk: Weather with Atmosphere — Privacy Policy

_Last updated: 14 November 2026_

Murk is a weather app. It has no accounts, no advertising, no analytics and no tracking. This page says exactly what leaves your phone, who receives it, and why.

## What Murk uses

| Data | Where it goes | Why |
| --- | --- | --- |
| **Location** (only if you choose "Use Current Location"), or the coordinates of a city you saved | Sent to the weather services below, rounded to about 1 km (0.6 mi). With **Approximate location** on, rounded to about 11 km (7 mi). | To retrieve the forecast, air quality and weather alerts for that place |
| **Saved cities** | Stored on your phone only | So you can switch between places |
| **Settings** (units, skin, notification choices) | Stored on your phone only | To remember your preferences |
| **Subscription status** (whether Murk Pro is active) | Purchases are processed by Apple. Murk keeps an on/off flag on your phone. | To unlock Murk Pro features |
| **Diagnostics** | None collected by Murk | — |

Murk asks for location permission "While Using the App" only, and only after you choose "Use Current Location". It never asks for "Always" access. If you decline, city search and saved cities work fully.

## Who receives data

Murk talks directly to these services over HTTPS. There is no Murk server in between.

- **Open-Meteo** (forecast and air quality): receives the rounded coordinates of the place being shown. <https://open-meteo.com/en/terms>
- **US National Weather Service, api.weather.gov** (official alerts): receives the rounded coordinates of the place being shown. <https://www.weather.gov/privacy>
- **Apple** (App Store purchases, and Apple's own city search and place names): governed by Apple's privacy policy. <https://www.apple.com/legal/privacy/>

Like any internet request, these services can see your IP address. Murk sends no name, email address, device identifier or advertising identifier, and does not combine your data with data from other apps or sites.

## What stays on your phone

- The last forecast for recently viewed places, so Murk works offline. Files are named with a hash (not coordinates or city names), are protected by iOS file protection, and are deleted after 48 hours.
- A small forecast summary shared with Murk's widgets through the app's private App Group. It holds the place name, coordinates rounded to about 11 km, and the temperatures and conditions the widgets show.
- A list of weather-alert identifiers already notified, kept for 14 days so you aren't notified twice.

Murk keeps no history of where you have been.

## Notifications

Murk asks for notification permission only when you turn on a notification in Settings. Every notification is about weather you chose to hear about.

## Retention and deletion

Murk has no server-side data about you, so there is nothing for us to delete. Everything Murk stores is on your phone and is removed when you delete the app. Forecast caches expire on their own as described above.

## Changing your mind

- **Location:** iOS Settings › Privacy & Security › Location Services › Murk, or "Stop using my location" in Murk's settings.
- **Notifications:** iOS Settings › Notifications › Murk, or the switches in Murk's settings.
- **Subscription:** iOS Settings › your name › Subscriptions, or "Manage Subscription" in Murk.

## Children

Murk is a general-audience weather app and does not knowingly collect personal information from anyone.

## Changes and contact

If this policy changes, the date above changes and the new version is published here. Questions: <https://github.com/rilwan11/murk/issues>
