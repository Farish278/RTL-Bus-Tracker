# Network and map caching

The app uses direct RTL requests. No proxy or hosted service is required.

## Request behavior

- A live subscription has one immediate coordinate cycle per route. Optional v3 bus details are merged after coordinates are published. Complete coordinate responses skip v3.
- Successful live cycles retain the eight-second delay after completion. Failed coordinates back off for 16, 32, then 60 seconds, with positive jitter. Longer Retry-After values take precedence. Requests have 20-second connection, send, and receive limits; an unrelated six-second Future timeout no longer discards valid coordinates.
- Static routes and geometry retain a seven-day freshness period. ETA retains sixty seconds. Memory entries avoid repeated database decoding. Expired cached data is returned immediately and refreshed once per resource; updates reach visible consumers.
- Catalogue refresh is shared by area lists, routes, and schedules. Multi-route schedule refresh downloads the catalogue once. Cache-write failures do not discard successful network results.
- The scheduler prioritizes coordinates over static data and optional enrichment. The UI starts with two request slots; once it confirms no alert service is running it can use four. Before starting the service it drains to two slots; the service has two of its own.
- Geometry, ETA, and coordinates load independently. Route selection remains interactive. Failed routes retain clearly labelled last-known positions; a successful empty coordinate response clears that route.
- Route selection cancels obsolete geometry/ETA work. Removing the last live consumer cancels its transport. Shared coordinates needed by another consumer remain in flight.

## Alerts and lifecycle

The foreground service owns map polling while running. The UI transfers its route subscription using service messages and renews a three-second view heartbeat. The service expires abandoned views after fifteen seconds. When the service stops, the visible UI resumes local polling. Hidden map screens, including navigation to Settings, release their live subscriptions.

Alert-only routes retain the forty-five-second service cadence and use coordinates without optional metadata. Map snapshots evaluate alerts for their own route only. A failed route does not suppress successful route checks, and network failures cannot stop the service while persisted alerts remain active.

Persisted bus snapshots are historical display data after restart. They cannot trigger alerts. Only current successful coordinate results can be used for evaluation. Alert preferences reload across isolates, and list mutations are serialized using a SQLite transaction. A separate notification claim table prevents duplicate sends during concurrent checks; unsent claims can recover after thirty seconds. The database upgrades from version 1 to 2 without clearing the transit cache or alerts.

## Map tiles

The renderer remains flutter_map 8.3.0. Both themes now use the same OpenStreetMap tile URL. Dark mode applies a local inverted-luminance treatment to the basemap only; route lines, markers, and app controls retain their own colors. Theme changes reuse the same tile bytes and do not request a second basemap.

The former CARTO dark endpoint returned an API-key-required message embedded in tile images, so an HTTP-error callback could not reliably detect it. That endpoint and its attribution/fallback UI are removed from the map. Previously cached CARTO images use different URLs and cannot be read by the new basemap. No API key, account setup, or transit-data reset is needed.

Static routes and stops reuse their rendered layer widgets between live updates.

The explicit disk cache retains the existing 1 GB soft limit and HTTP freshness handling. Settings has separate transit-cache and map-cache clearing, plus map-cache size and session hit/miss counts. Map cache storage can be evicted by the operating system. There is no bulk tile downloading or offline area-pack feature.

## Verification

Run:

~~~sh
flutter pub get
flutter analyze
flutter test
flutter build bundle --debug --no-pub
~~~

Tests cover request sharing and counts, the four-request cap and service reservation, progressive loading, cancellation with multiple consumers, cache-write failures, stale refresh notifications, eight-second successful polling and failure recovery, Retry-After, historical positions, alert-route isolation and notification recovery, service handoff, and map disk-cache persistence across provider recreation.

A transport simulation uses 256 Kbps throughput and 800 ms latency to verify that positions arrive while details remain pending. The disk-cache test writes tiles, recreates the provider, checks equivalent-subdomain reuse, and clears the cache. These are automated simulations and provider lifecycle checks, not physical-device bandwidth benchmarks or an Android process-restart test.

Debug Settings shows per-endpoint request, error and cancellation counts, declared Content-Length bytes, and decoded JSON payload size. NetworkMetrics also records summed request latency. Content-Length may be missing; decoded payload size is not a wire-byte measurement. Service and UI metrics are per isolate. No real RTL traffic is generated by the test suite.

Physical-device follow-up: compare the installed APK with this checkout, revisit light/dark areas after terminating the app, test notifications with the screen off, and capture actual RTL/tile traffic on a throttled mobile connection.
