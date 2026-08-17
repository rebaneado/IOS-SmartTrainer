# SmartTrainer for iOS / iPadOS

A native SwiftUI app for ERG-mode control of a Saris H3 (or any FTMS-compatible
smart trainer) over Bluetooth, plus an optional heart rate strap. This is the
**iPhone/iPad counterpart** to the SmartTrainer web app — rewritten in Swift so
it can actually drive the trainer from iOS.

> **Why a separate native app?** The web version can never control a trainer
> from an iPhone/iPad: Apple's Safari/WebKit doesn't implement Web Bluetooth at
> all. A native app uses Apple's own **CoreBluetooth** framework instead, which
> has no such restriction — so trainer + HR control works on iPhone and iPad.

## What it does

- Connects directly to your trainer over Bluetooth (FTMS — Fitness Machine
  Service) and drives ERG mode by pushing target watts as the workout runs.
- **Comes pre-loaded with a starter Ironman-distance bike plan** — 84 planned
  workouts, ordered by date — seeded into the library on first launch so
  there's something to ride immediately. The data is bundled at
  `SmartTrainer/Resources/ironman-2026-plan.json`; delete the workouts or hit
  "Reload plan" to bring them back. Nothing in the bundled plan or the app's
  defaults (FTP, HR zones) identifies any specific person — see
  [No personal data baked in](#no-personal-data-baked-in).
- **TrainingPeaks:** TrainingPeaks' API is invite-only for commercial partners
  (no self-serve access for an indie app, and they're not accepting new
  partners at the moment) — there's no "Sign in with TrainingPeaks" button
  possible today. Instead, export a workout from TrainingPeaks as
  **`.zwo`/`.erg`/`.mrc`** and use **Import workout** below; that's the same
  mechanism used for Zwift/TrainerRoad/etc. files.
- Also imports structured workouts from **`.erg`/`.mrc`** (recommended — plain
  text, no ambiguity) and **`.zwo`** (Zwift). Each workout is saved to an
  on-device library (survives restarts), shows an interval summary, and every
  step's duration/target can be edited.
- Live ride screen with the current step (color-coded by intensity) + countdown,
  a full-workout completion timeline, an upcoming-steps strip, and color-coded
  tiles for power, target, cadence (green), speed (aqua), and distance (yellow) —
  matching the web app's look. The **heart-rate tile is colored by HR zone**
  (Z1 blue → Z5 red, from your own zones, set in Settings) and labeled with the
  zone; the ride summary adds a **time-in-heart-rate-zones** breakdown.
- **Manual control:** nudge target ±5W, or toggle ERG off for manual resistance.
- **Auto-pause:** if power and cadence read zero for 5 seconds, the ride pauses
  itself (with a clear indicator) and resumes when you start pedaling again.
- **Optional heart rate strap:** connect any standard BLE strap (Garmin HRM,
  Wahoo TICKR, Polar) independently of the trainer.
- **Trial mode:** start any workout with no trainer connected — it runs against
  simulated numbers so you can preview the whole flow.
- **Strava, one-time sign-in:** connect your Strava account once (Settings —
  see [Setting up Strava](#setting-up-strava-upload) below); every ride's
  summary screen then gets a **"Log ride to Strava"** button that uploads the
  `.tcx` directly via Strava's API — no share sheet needed.
- Also records the ride and exports it as a **`.tcx`** activity file via the
  iOS share sheet — upload it to TrainingPeaks or Garmin Connect, or email it
  to yourself.

## What's NOT in this v1 (vs. the web app)

- **`.fit` import/export.** The web app's custom FIT binary reader/writer was
  ~1500 lines and the source of every parsing bug we hit. For iOS v1 the app
  supports `.erg`/`.mrc`/`.zwo` in and `.tcx` out (all plain text/XML). `.fit`
  can be added later.
- **Live TrainingPeaks account sync.** Not possible for an independent app —
  see above.

## Setting up Strava upload

Strava's API is genuinely self-serve for individuals — unlike TrainingPeaks,
no approval process, and it's free:

1. Go to <https://www.strava.com/settings/api> (log in with the Strava account
   you want rides uploaded to) and create an API application.
   - **Authorization Callback Domain:** enter exactly `smarttrainer` (just
     that word, no `https://`, no slashes) — that's the custom URL scheme this
     app registers for the OAuth redirect.
   - Anything else on the form (name, website, icon) can be anything.
2. Copy the **Client ID** and **Client Secret** it gives you.
3. In the app, open **Strava** on the dashboard, paste both in, and tap
   **Save**.
4. Tap **Connect to Strava** — this is the one-time sign-in. You'll get
   Strava's own login/consent screen; approve it and you're done.
5. From then on, every ride's summary screen has a **"Log ride to Strava"**
   button.

Your Client ID/Secret and OAuth tokens are stored in the iOS Keychain on your
device only — never committed to source control, never sent anywhere but
Strava's API.

## No personal data baked in

Everything that used to be one rider's specific data is now either empty by
default or clearly a generic starting point you're expected to change:

- **FTP** defaults to 200W — edit it in Settings.
- **Heart-rate zones** default to a generic five-zone split — edit all four
  boundaries in Settings to your own (from a lab test, TrainingPeaks, or your
  watch's estimate).
- **Strava credentials** are never bundled — you paste in your own.
- The bundled workout plan has no name, email, or other identifying data in
  it — it's just workout structure (durations/watts/steps). If you don't want
  it bundled at all for a public release, delete
  `SmartTrainer/Resources/ironman-2026-plan.json` and remove the
  `loadBundledPlan()` call in `SmartTrainer/State/Library.swift`'s `init()`.

## Requirements to build & run

You need a **Mac with Xcode 15+** (iOS 17 SDK). This project was authored on
Linux and has **not been compiled** — Swift's iOS SDK (CoreBluetooth, SwiftUI,
UIKit) only exists on macOS, so the first real build happens on your machine.
The pure workout-parsing logic was validated separately against real files, but
treat the first Xcode build as the first compile of the UI/BLE layer and expect
to fix a few small things.

### 1. Generate the Xcode project

The `.xcodeproj` is **not** committed — it's generated from `project.yml` by
[XcodeGen](https://github.com/yonwoo9/XcodeGen), which avoids fragile
hand-edited project files.

```sh
brew install xcodegen      # one-time
cd IOS-SmartTrainer
xcodegen generate          # creates SmartTrainer.xcodeproj
open SmartTrainer.xcodeproj
```

If you'd rather not use XcodeGen, you can instead create a new "App" project in
Xcode (SwiftUI lifecycle, iOS 17) and drag the `SmartTrainer/` folder in — but
XcodeGen is much faster.

### 2. Set your signing team

CoreBluetooth needs a real signed build to run on a device (the Simulator has
no Bluetooth radio). In Xcode → target **SmartTrainer** → **Signing &
Capabilities** → pick your **Team** (any free Apple ID works for on-device
testing). The bundle id defaults to `com.rebaneado.smarttrainer` — change it in
`project.yml` (or Xcode) if you want a different one; it must be globally unique
to ship on the App Store.

### 3. Run on your iPhone/iPad

Plug in the device, select it as the run destination, and press ▶. The first
launch will ask for Bluetooth permission (the prompt text is in `Info.plist`).
**Bluetooth features do not work in the Simulator** — always test on a physical
device.

## Submitting to the App Store

This is the part only you can do — it needs your Apple account and money:

1. **Apple Developer Program** membership — $99/year, at
   <https://developer.apple.com/programs/>. Required to submit to the store
   (free accounts can only sideload to your own devices).
2. In **App Store Connect** (<https://appstoreconnect.apple.com>), create a new
   app record with the bundle id above.
3. In Xcode: **Product → Archive**, then **Distribute App → App Store Connect**.
4. Fill in the listing: screenshots (iPhone + iPad), description, keywords, and
   a **privacy policy URL** (required — see below).
5. Submit for review.

### Privacy policy & nutrition labels

This app still has **no backend of its own** — everything stays on-device —
but once Strava sign-in is added it does talk to a third party, so the
privacy nutrition label in App Store Connect isn't "collects no data"
anymore. Answer it accurately:

- **Data linked to identity:** none you collect — Strava handles its own
  account/auth; you never see or store the rider's Strava password.
- **Data used to track:** none.
- **Third-party SDK:** none (Strava is called via plain HTTPS, no SDK).
- Your **privacy policy** page (required, needs a real URL) should say
  plainly: the app stores workout/ride data and, if the rider connects
  Strava, an OAuth token, on-device only; the app talks directly to Strava's
  API to upload rides if the rider chooses to; no data is sold, shared, or
  sent to any server you operate (because you don't operate one). A single
  static page (GitHub Pages, Notion, etc.) satisfies this.

### Likely App Review notes for this app

- **Bluetooth usage** is already justified with a clear `NSBluetoothAlwaysUsageDescription`
  string. Keep it accurate.
- The `bluetooth-central` **background mode** is declared so an in-progress ride
  keeps its trainer connection if the screen locks. If you don't need background
  operation, removing it from `project.yml`/`Info.plist` makes review simpler.
- **Strava sign-in:** reviewers will test it, so make sure your own Strava API
  app (Client ID/Secret you enter in Settings) is live and its Authorization
  Callback Domain is set correctly (see [Setting up Strava
  upload](#setting-up-strava-upload)) before submitting — a broken OAuth flow
  is a common rejection reason.
- No account system of your own, no tracking, no third-party SDKs — which
  keeps review comparatively light.

## Project layout

```
project.yml                      # XcodeGen project definition (source of truth)
SmartTrainer/
  App/SmartTrainerApp.swift      # @main entry point
  BLE/                           # CoreBluetooth FTMS trainer + HR sensor + sim
  Workout/                       # model, .erg/.mrc + .zwo parsers, interval grouping
  ERG/                           # ERG execution engine, ride recording
  Export/                        # TCX activity exporter
  Strava/                        # OAuth sign-in + ride upload (Keychain-backed)
  State/                         # UserDefaults-backed library + settings
  Views/                         # SwiftUI screens + shared components
  Assets.xcassets/               # app icon + accent color placeholders
  Info.plist
```

## Notes / things to verify on real hardware

- The FTMS control-point protocol and Indoor Bike Data parsing follow the
  Bluetooth SIG spec and mirror the web app's (which uses the identical byte
  layout), but real-trainer quirks haven't been verified firsthand here.
- A **placeholder app icon** is included (a blank 1024px slot). Add a real icon
  in `Assets.xcassets/AppIcon.appiconset` before submitting — the store requires
  one.
- Editing a workout step fixes it to an explicit wattage (not %FTP), matching
  the web app's behavior.
