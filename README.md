# My Weather

A small, text-first personal weather app for iPhone, iPad, and Mac. **Today** shows essential weather and compact daily weather blocks for up to five saved cities. **5-Day Forecast** shows today and the following four days with temperature values, condition badges, and full-day weather gradients. Both views keep the same city order. The interface uses Verdana and is always dark. It displays saved weather immediately and only fetches when **Refresh** is pressed on Today or after a city is added—not on launch, foreground, or switching views.

The complete portfolio product requirements document is available at [docs/My_Weather_Portfolio_PRD.pdf](docs/My_Weather_Portfolio_PRD.pdf).

## Current version: 1.6.0 (build 10)

- Five compact forecast rows per city: a day/date, readable daily condition badge, minimum and maximum temperatures, and one full-day horizontal weather bar.
- The approved two-icon switch uses the actual app icon for **Today** and a calendar for **5-Day Forecast**. Swipe left/right across the **My Weather** title area as an alternative.
- Stable city identity/order and a spring transition between views, respecting the system's **Reduce Motion** setting.
- Each day's gradient uses its own hourly forecast and actual supplied sunrise/sunset times. Transitions are not forced to 06:00 or other fixed daily cutoffs.
- Today retains current temperature beside the city name, its local clock beneath, low/high, humidity, condition badge, precipitation chance, and labeled periods. No city-detail navigation returns.
- Existing saved cities and weather remain compatible. No new permissions, dependencies, background tasks, or requests when switching views.

After updating from an older version, tap **Refresh** on Today once to load the new five-day data. Until then, existing weather stays visible and the forecast view explains how to load it.

## Today: daily weather blocks

Each city has a compact stack of up to six colored periods beside its weather values. Times use a 24-hour clock in **that city's local time zone**; `24` means the midnight ending the day. The small date label identifies the cached forecast day. The main **Last Updated** timestamp uses the device's time zone.

City clocks and **Now** dots update locally each minute, without fetching weather or changing **Last Updated**. Time zones follow daylight-saving changes automatically; India uses **IST**, while other zones show their short name or GMT offset. At a period boundary the dot moves to the next bar. If the saved forecast is from a different day, its values remain visible but no **Now** dot appears. Refresh manually to fetch the latest weather.

- Adjacent similar hours are combined. Mixed-period labels prioritize higher-severity weather rather than describing the whole period as sunny. Rain, snow, freezing rain, fog, and storms have dedicated categories, including at night.
- Fresh data uses **Night**, **Sunny**, **Sun / Cloud**, **Cloudy**, and weather-event categories. Periods split at the provider's hourly boundaries and supplied sunrise/sunset. Older cached **Dawn**, **Low Light**, and **Dusk** categories still decode; fresh data does not invent twilight periods.
- These are native SwiftUI views with text and VoiceOver labels, not downloaded images. The layout measures weather text before choosing columns, gives spare width to the bars, and keeps all bars equally sized. Larger text sizes and narrow windows stack the blocks below the city values.
- Blocks are cached with each weather snapshot and stay visible offline. When upgrading from a version without blocks, press **Refresh** once to fetch the required hourly data.
- One combined request per city supplies both views. `past_days=1` and `forecast_days=6` provide a padding day on either side of the five displayed dates, covering local daylight-saving boundaries.

## 5-Day Forecast: full-day weather bars

- A bar spans the city's local midnight to the next midnight. Its colors show the weather distribution **over time**, not a temperature scale. Short gradients soften actual boundaries without moving their stored times or claiming minute-precise weather forecasts.
- Minimum temperature is on the left; maximum is on the right. The header states Celsius units. There is no **Low**, **High**, **Daily Range**, or **Now** text, and no city clock, timezone text, humidity, or precipitation probability in this view.
- For today's cached snapshot, the current-temperature value sits above a red, white-outlined dot. Here the dot's horizontal position represents elapsed local-day time. On **Today**, the dot instead stays near the right edge of the active labeled block; these are intentionally different indicators using the same visual style.
- Tracks share a 14-point height and equal widths, filling the space between the temperature values. Large text can move temperatures above the track. Condition badges reuse the existing dark-mode palette and full labels.
- Exact hourly/solar periods are retained before Today's compact list is reduced to at most six blocks. Each forecast date uses its own periods, including daylight-saving and half-hour transitions. A DST day receives its own clock ticks when a normal 24-hour axis would be misleading.
- If hourly data is unavailable, daily temperatures remain visible with a neutral bar and **Hourly Unavailable**. If fewer than five dates arrive, the app indicates the missing days rather than inventing them.

The five dated rows remain the last successful snapshot until refresh; they do not automatically roll forward after midnight. Old dates stay visible. The current-temperature annotation and dot appear only when the first cached forecast date is still today. A moving dot does not mean that weather has just been refreshed. **Refresh** and city editing are available on Today only.

## Data structure

| Model | Contents |
| --- | --- |
| `SavedCity` | Provider ID, name, region/country, coordinates, IANA timezone. |
| `WeatherSnapshot` | `current`, `today`, optional `dayTimeline`, optional `forecastDays`. |
| `DailyForecast` | Local-midnight `date`, daily `weather` (min/max, condition, precipitation), optional `timeline`. |
| `DayTimeline` | Date label, timezone, compact `blocks`, optional exact `periods`. |
| `DayWeatherBlock` | Absolute start/end dates, visible and accessible time labels, weather categories. |
| `StoredWeatherState` | Snapshots keyed by city ID plus the global `lastUpdated` date. |

New fields are optional so earlier caches still decode. One combined HTTPS forecast request per city contains current temperature/humidity/code, hourly time/code/daylight flags, and daily time/min/max/code/precipitation probability/sunrise/sunset. Switching screens reads the same local snapshot.

Forecast field definitions: [Open-Meteo documentation](https://open-meteo.com/en/docs).

## Install on an iPhone, iPad, or Mac

1. Install Xcode from the Mac App Store.
2. Open `MyWeather.xcodeproj`.
3. Select the **MyWeather** target, open **Signing & Capabilities**, and choose your Apple Account team.
4. For iPhone or iPad, connect the device, enable Developer Mode if prompted, select it as the run destination, and press Run.
5. For Mac, select **My Mac** as the run destination and press Run. The project also supports Mac Catalyst.

An unpaid Apple Account uses Personal Team signing, so the app must be rebuilt and reinstalled periodically.

The public project does not include a development team or signing credentials. Choose your own team locally; do not commit personal signing changes. Updating an existing installation with the same bundle identifier and signing team preserves its saved cities and cache.

## Data and privacy

- Weather forecasts and geocoding are provided by [Open-Meteo](https://open-meteo.com/) over HTTPS. City-search data is based on [GeoNames](https://www.geonames.org/). Requests are limited to the exact forecast and geocoding hosts.
- Network sessions do not retain cookies, credentials, or response caches.
- No API key, account, location permission, analytics, advertisements, or tracking are used.
- No camera, microphone, photo, contacts, calendar, Bluetooth, notification, or background permissions are requested.
- Only the selected city records, last successful weather values, and refresh time are stored on the device.

The Mac build uses App Sandbox with outgoing network access as its only additional entitlement.

## Tests

- In Xcode, choose **Product → Test**.
- The core tests can also run from Terminal with `swift test` in this folder.

Version 1.6.0 validation includes **41 core tests**, **59 iOS tests**, and **53 Mac tests**. Coverage includes five-day selection, distinct solar/hourly periods per date, gradient proportions, DST and half-hour changes, old/new cache compatibility, no fetching on view opening, failed-refresh cache retention, city order, and responsive layout. Existing badge tests check every daily condition, at least **4.5:1 text-to-fill contrast**, and at least **3:1 border-to-fill contrast**.

The iOS suite produces screenshots at small-phone, phone, landscape, and tablet widths, including the largest Dynamic Type setting, Today/forecast screens, and missing hourly data. Live API smoke checks on October 16, 2026 returned five complete forecasts for Montreal and Mumbai. Version 1.6.0 was installed and launched on a physical iPhone; saved cities/order and cached weather matched byte for byte before and after installation. The sanitized public source separately passed the core and Mac test suites and all 59 iOS tests on both iPhone and iPad simulators, plus unsigned iOS and Mac Release builds, without personal signing credentials.

Necessary wrapping and vertical scrolling are intentional on small screens and at larger text sizes. These checks do not constitute exhaustive testing of every device, OS version, or accessibility configuration.

Known limits: the global **Last Updated** advances if any city succeeds, so another city may retain older data; per-city freshness and a stale/offline banner are not implemented. Full VoiceOver and swipe-animation interaction coverage, multi-city partial-failure tests, and continuous live-provider checks remain follow-ups. The public documentation credits data providers; visible in-app provider attribution remains a follow-up before public binary distribution.

## App size

The unsigned iOS Release app built from this public source on October 16, 2026 contains **3,344,727 logical file bytes: 3.34 MB (3.19 MiB)**. This is the app bundle, not an App Store download or the storage reported by an installed device. Signing, device thinning, filesystem allocation, and cached weather can change those sizes.

## Credits

Created by **Nikhil Sharma**, with implementation assistance from **ChatGPT models**. Weather and city-data credits are listed above; their service terms and attribution requirements apply separately from this project's code license.

## License

My Weather is available under the [MIT License](LICENSE). It may be used, modified, and redistributed, including commercially, provided the copyright and license notice are retained.
