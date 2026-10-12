# My Weather

A small, text-first personal weather app for iPhone, iPad, and Mac. For up to five saved cities, its main screen shows current temperature in Celsius, today’s low and high, humidity, whole-day conditions, and a clearly named precipitation chance. Cities can be reordered and the order is saved. The interface uses Verdana, is always dark, and shows when weather was last updated. It does not fetch weather when the app opens: it immediately displays the last successfully refreshed values, then replaces them when **Refresh** is pressed or after a city is added.

The complete portfolio product requirements document is available at [docs/My_Weather_Portfolio_PRD.pdf](docs/My_Weather_Portfolio_PRD.pdf).

## Install on an iPhone, iPad, or Mac

1. Install Xcode from the Mac App Store.
2. Open `MyWeather.xcodeproj`.
3. Select the **MyWeather** target, open **Signing & Capabilities**, and choose your Apple Account team.
4. For iPhone or iPad, connect the device, enable Developer Mode if prompted, select it as the run destination, and press Run.
5. For Mac, select **My Mac (Mac Catalyst)** as the run destination and press Run.

An unpaid Apple Account uses Personal Team signing, so the app must be rebuilt and reinstalled periodically.

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

## License

My Weather is available under the [MIT License](LICENSE). It may be used, modified, and redistributed, including commercially, provided the copyright and license notice are retained.
