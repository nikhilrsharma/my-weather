# My Weather

A small, text-first personal weather app for iPhone, iPad, and Mac. For up to five saved cities, its main screen shows current temperature in Celsius, today’s low and high, humidity, whole-day conditions, a clearly named precipitation chance, and compact daily weather blocks. Cities can be reordered and the order is saved. The interface uses Verdana, is always dark, and shows when weather was last updated. It does not fetch weather when the app opens: it immediately displays the last successfully refreshed values, then replaces them when **Refresh** is pressed or after a city is added.

The complete portfolio product requirements document is available at [docs/My_Weather_Portfolio_PRD.pdf](docs/My_Weather_Portfolio_PRD.pdf).

## Current version: 1.5.2 (build 9)

- Current temperature sits next to the city name (for example, **Mumbai 25°C**). The city-local 24-hour clock and relevant time zone appear on the line below (for example, **03:15 IST**).
- Daily conditions such as **Sunny**, **Rain**, and **Cloudy** appear in compact rounded badges. Weather-related colors, opaque dark fills, light text, and visible borders keep them readable in dark mode. Humidity remains plain text; only the daily condition gets a badge.
- A red **Now** dot centered inside the current weather bar, fixed near the right edge with a small gap. Dots line up vertically; they are not progress indicators.
- Equal bar widths and heights across every saved city. Bars now fill their available horizontal space, leaving the normal row margin at the right edge.
- Responsive layout: wider windows place bars beside weather values; compact widths and accessibility text sizes put full-width bars below. Content reflows after rotation or resizing, without shrinking the user's chosen text size.
- Long city names and temperatures move onto separate lines when needed. Humidity and condition stay inline when they fit; otherwise the badge moves below and its label wraps as needed. At large text sizes, time and condition can stack inside every bar. Main and About content scroll on short screens.
- Compact daily weather blocks with readable time ranges and gradients around light changes.
- Consistent capitalization across short interface labels, including **Low Light**, **Sun / Cloud**, and **Last Updated**.
- Existing city lists and cached weather remain compatible. No additional permissions, dependencies, or background fetching.

## Daily weather blocks

Each city has a compact stack of up to six colored periods beside its weather values. Times use a 24-hour clock in **that city's local time zone**; `24` means the midnight ending the day. The small date label identifies the cached forecast day. The main **Last Updated** timestamp uses the device's time zone.

City clocks and **Now** dots update locally each minute, without fetching weather or changing **Last Updated**. Time zones follow daylight-saving changes automatically; India uses **IST**, while other zones show their short name or GMT offset. At a period boundary the dot moves to the next bar. If the saved forecast is from a different day, its values remain visible but no **Now** dot appears. Refresh manually to fetch the latest weather.

- Adjacent similar hours are combined. Mixed-period labels prioritize higher-severity weather rather than describing the whole period as sunny. Rain, snow, freezing rain, fog, and storms have dedicated categories, including at night.
- **Night**, **Dawn**, **Sunny**, **Sun / Cloud**, **Cloudy**, **Low Light**, and **Dusk** use distinct colors and gradients. Light transitions are approximate hourly summaries around forecast sunrise/sunset, not exact astronomical twilight times.
- These are native SwiftUI views with text and VoiceOver labels, not downloaded images. The layout measures weather text before choosing columns, gives spare width to the bars, and keeps all bars equally sized. Larger text sizes and narrow windows stack the blocks below the city values.
- Blocks are cached with each weather snapshot and stay visible offline. When upgrading from a version without blocks, press **Refresh** once to fetch the required hourly data.
- One combined forecast request per city includes current and daily fields, hourly weather codes/daylight flags, and sunrise/sunset. A day of padding on each side covers local daylight-saving boundaries; only the selected local day is displayed.

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

Version 1.5.2 validation: **34 core tests**, the **48-test iOS suite on both iPhone and iPad simulators**, and **45 Mac tests**, including weather categories, local daylight-saving days, city clocks, Now boundaries, cache compatibility, full-width bar allocation, resize round trips, shared sizing, and large-text reflow. Badge tests cover every daily condition, at least **4.5:1 text-to-fill contrast**, at least **3:1 border-to-fill contrast**, and padding-aware column measurement. The iOS tests produce reviewable screenshots at small-phone, phone, landscape, and tablet widths, plus the largest Dynamic Type setting, all badges, missing/legacy weather, and the main/search/About screens. Signed iPhone, unsigned public-source iOS, and native Mac Release builds were also validated.

Necessary wrapping and vertical scrolling are intentional on small screens and at larger text sizes. These checks do not constitute exhaustive testing of every device, OS version, or accessibility configuration.

## Credits

Created by **Nikhil Sharma**, with implementation assistance from **ChatGPT models**. Weather and city-data credits are listed above; their service terms and attribution requirements apply separately from this project's code license.

## License

My Weather is available under the [MIT License](LICENSE). It may be used, modified, and redistributed, including commercially, provided the copyright and license notice are retained.
