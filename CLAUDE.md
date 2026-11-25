# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**subbi** is a SwiftUI iOS app for tracking subscriptions (costs, upcoming payments, calendar, stats, payment reminders). Single target and scheme `subbi`, bundle ID `com.kamil-kajta.subbi`, deployment target iOS 27.0, dark mode only. There are no package dependencies and no test target.

Accounts and subscription sync are handled by the backend in the sibling repo **`../subbi-backend`** (NestJS + Prisma + SQLite, with Swagger docs at `/docs`; see its README for the API). Run it with `npm run dev` there.

The backend URL comes **only** from the `API_BASE_URL` build setting on the target, set per configuration (Debug / Release). The value reaches the app through the `SubbiAPIBaseURL` key in `subbi-Info.plist`, which `AuthStore.defaultServerURL` reads. There is no in-app field for it. To test on a phone, point Debug at the Mac's LAN address (e.g. `http://192.168.x.x:3000` or `http://<LocalHostName>.local:3000`); production needs an `https://` URL.

The source language is **Polish**: UI string keys and code comments are written in Polish. English is a translation, kept in `subbi/Localizable.xcstrings` (`developmentRegion = pl`).
- The default is the system language (`AppLanguage.system`: the first supported entry in `Locale.preferredLanguages`, otherwise English). It applies when nothing is saved, and registration resets the language to it.
- The user picks the language in Settings (`AppLanguage` in `Models/Language.swift`). It changes live without a restart: `subbiApp` sets `\.locale` and rebuilds the view tree with `.id(store.language)`, keeping the selected tab.
- SwiftUI literals such as `Text("…")` translate through `\.locale`. Strings built in code **must** use `String(localized: "…", bundle: .appLanguage)`, because a bare `String(localized:)` follows the system language, not the in-app choice.
- Numbers in text go through `Plural.hours` / `Plural.days`, which handle Polish forms like `godzinę` / `godziny` / `godzin`.
- Dates and amounts use `AppCal.locale` / `AppCal.cal`, which depend on the language.
- Backend errors arrive in Polish. `AppLanguage.translateServerMessage` maps them through manual catalog entries (`extractionState: manual`); when you add a backend message, add its English translation there too.
- When you add a string, give it an `en` translation in the catalog. Xcode adds the key on build.

## Build

```sh
# Build for the simulator
xcodebuild -project subbi.xcodeproj -scheme subbi -destination 'generic/platform=iOS Simulator' build

# Build and run on a specific simulator (list them with: xcrun simctl list devices)
xcodebuild -project subbi.xcodeproj -scheme subbi -destination 'platform=iOS Simulator,name=<device>' build
```

Extra Info.plist keys (local-network permission text, the ATS `NSAllowsLocalNetworking` exception for `http://` to the LAN backend) live in `subbi-Info.plist` at the repo root. It sits outside `subbi/` on purpose, so the synchronized group doesn't copy it as a resource. Xcode merges it with the generated `INFOPLIST_KEY_*` settings.

The project uses Xcode's file-system-synchronized groups, so new `.swift` files under `subbi/` get picked up automatically. Don't edit `project.pbxproj` to add files.

## Architecture

- **Default MainActor isolation** (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`): everything is main-actor unless marked `nonisolated` (as `SubscriptionStore.format` is, so it can be captured in the notification closure).
- **`SubscriptionStore`** (`Stores/SubscriptionStore.swift`) is the single `@Observable` source of truth for subscriptions and settings. `subbiApp` creates it and passes it explicitly as `store:` to every view; it is also injected with `.environment(store)`. Views that need bindings use `@Bindable var store`.
  - Persistence goes to `UserDefaults`: subscriptions are stored as JSON under `subscriptions.v1`, and each setting has its own key. Every property persists in its own `didSet`.
  - Any change to subscriptions, currency, or reminder settings calls `refreshReminders()`. That runs `NotificationManager.reschedule`, which **removes all pending notifications** and schedules up to 3 upcoming payments per subscription over the next 120 days, firing exactly `reminderHours` × 3600 s before the payment moment (the time of day stored in `firstPayment`). Trigger components are in UTC, so DST and time-zone changes do not shift them. `dueHour` (9) is only the default time in the add form and sample data.
  - `init` migrates the old `reminderDays` setting to `reminderHours`. On first launch with no saved data it seeds `sampleData()`.
  - Deactivation (long press in `SubscriptionsListView`, irreversible) sets `Subscription.deactivatedAt`. The edit form can move that date (never into the future), and `store.update` never changes whether a subscription is active. `occurrences` stops there, so earlier payments stay in the calendar and bar chart. Use `activeSubscriptions` for totals and counts.
  - Derived data (totals, `upcoming`, `payments(inMonthOf:)`, `monthTotals`) is computed on the fly. Nothing is cached.
- **`AuthStore`** (`Stores/AuthStore.swift`) owns the session and the sync. `subbiApp` shows `LoginView` until `auth.isLoggedIn`. The token is kept in the Keychain (`Keychain.swift`); the user profile and server URL are in `UserDefaults`.
  - Every user change to `store.subscriptions` calls `store.onSubscriptionsChange`. That marks the list dirty (persisted as `sync.dirty`) and, after a debounce, PUTs the **whole list**.
  - Writing data that came from the server must go through `store.replaceSubscriptions(_:)`, which doesn't trigger a push.
  - On login or registration, a non-empty server list replaces the local one; an empty server list is filled with the local one. `refresh()` runs whenever the scene becomes active: it pushes dirty changes first, then pulls the server list.
  - Any 401 ends the session. Logout clears the subscriptions from the device.
- **`APIClient`** (`Stores/APIClient.swift`) is a stateless URLSession wrapper. JSON dates are ISO 8601. The server's Polish `{ "error" }` messages come through as `APIError.localizedDescription`, so they can be shown to the user directly. The `Subscription` Codable shape is the API contract: change it together with `subbi-backend/src/schemas.ts`.
- **Date logic** (`Models/Models.swift`): always use `AppCal.cal` (Gregorian, Monday first, `pl_PL`) and `AppCal.locale`, never `Calendar.current`. Payment dates are generated by `Subscription.occurrences(from:to:)`, which adds whole months or years to `firstPayment`. Money formatting goes through `store.money(_:)`.
- **`Service.catalog`** is the hard-coded list of preset services (name, icon, brand color, category, default price) used by the add form and the sample data.
  - An icon written as `brand:<name>` is a logo tile from `Assets.xcassets/Brands`. The tiles are generated by `tools/brand-icons` (sources and licenses are in its README).
  - Views pass `sub.iconSymbol` (not `sub.symbol`) to `ServiceIcon`. `iconSymbol` resolves the logo by service name, so older synced subscriptions that still store SF Symbols show logos too.
- **Launch animation**:
  - The iOS launch screen is a plain `LaunchBackground` color (`UILaunchScreen` in `subbi-Info.plist`).
  - `subbiApp` then overlays `SplashView`, which plays `Splash/splash.mp4` once per cold launch and fades into the app. Tapping skips it; it does not play when Reduce Motion is on.
  - The sound `Splash/audio.m4a` (whoosh, two bass hits, chimes and reverb, generated by `tools/splash/make_audio.py`) is merged with the video into a single `AVMutableComposition` (`SplashMedia`) and played by one `AVPlayer`. The last video frame is stretched to the end of the sound.
  - The audio session (`.playback` + `.mixWithOthers`) is activated off the main thread with `@concurrent`. Under approachable concurrency, a plain `nonisolated async` function would still run on the main actor.
  - In Debug, splash diagnostics are printed with a `[Splash]` prefix.
  - The video is generated by `tools/splash` (see its README for the color-matching note).
- **Navigation** (`Views/ContentView.swift`): a `TabView` with four tabs (home, calendar, stats, settings). The green "Dodaj subskrypcję" button on `HomeView` opens `AddSubscriptionView` as a sheet. Tapping a subscription in `SubscriptionsListView` or a payment in `CalendarView` opens the same view with `editing:` set (service picker hidden, delete button shown, saves through `store.update`).
- **Styling** (`Views/Theme.swift`): use the `Theme` colors, `.cardStyle()`, `.screenBackground()`, `ServiceIcon`, and `Color(hex:)`. Global UIKit tab bar and nav bar appearance is set in `subbiApp.init`. Charts use Swift Charts.
- **Feedback**: `SoundManager` plays system sounds and haptics, gated by `store.soundsEnabled`.
