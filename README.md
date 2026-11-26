# Upline

**Know it's them before you debug.**

Upline is a macOS menu bar app that finds every third party service your projects depend on and tells you the moment one of them goes down. It combines official status pages with live probes of the real API hosts, so you hear about an outage before the status page admits it.

## What it does

* **Zero setup detection.** Scans your code folders for git repos and reads `package.json`, lockfile manifests, `requirements.txt`, `pyproject.toml`, `Podfile`, `Gemfile`, `go.mod`, `pubspec.yaml`, Gradle files, Docker files, platform configs (`vercel.json`, `wrangler.toml`, `fly.toml`, `eas.json` and more), `.env` key names, hosts in env URLs and code, and git remotes.
* **90 services built in.** AI (Anthropic, OpenAI, Moonshot Kimi, Gemini, Groq, Mistral, DeepSeek, OpenRouter...), databases (Neon, Supabase, Upstash, MongoDB Atlas, PlanetScale, Turso, Firebase...), hosting, payments and fintech (Stripe, Plaid, Bridge, Circle, Wise...), auth (Privy, Clerk, Auth0...), email, messaging, analytics, web3 and dev tools. Unknown API hosts become custom services, watched by probe.
* **Two signals, not one.** Reads Statuspage, incident.io, Instatus and Status.io pages plus RSS and Atom feeds. At the same time it probes the real API host, and for databases opens a TCP connection to *your* database host. If the API stops answering while the status page still says fine, you get a **Suspected** alert.
* **Only what you use.** Detects regions from hosts (for example `eu-central-1` in a Neon or Supabase URL) and only alerts on matching status page components. You can pick components by hand too.
* **Is it me?** Before blaming anyone, Upline checks your own connection, DNS and captive Wi-Fi portals.
* **Wake check.** When the Mac wakes, unlocks or reconnects, Upline waits for the network, checks everything, and sends one summary: *"Neon partial outage since 3:40 AM. Affects sorbet-api, otp-inbox."* Silent when all is well. A second notification tells you when it's back.
* **Multi project aware.** Each service is checked once, however many projects use it. Projects you've edited in the last few hours (tracked with FSEvents, no extra permissions) get full alerts. Idle ones get a quiet dot. Dormant ones stay silent unless pinned.
* **Deep check (opt in).** For AI and API keys, Upline can confirm that your own key still works: invalid key, rate limited or out of credits. The key is read from the project's `.env` when the check runs, kept in memory and sent only to that service's own host.
* **Manual endpoints.** Watch your own production health route or anything else with a URL.

## Interface

A dark, glassy menu bar panel with a live radar where every service is a blip (hot projects on the inner ring, dormant on the edge, problems pulse red). Per service detail with a Swift Charts latency trace, incident timeline, component picker and deep check. Project cards show each repo's dependency health at a glance. Onboarding runs an animated scan of your repos. On macOS 26 with Xcode 26, the controls use Liquid Glass.

Keyboard: `⌘R` checks everything now, `Esc` or `⌘[` goes back.

## Build

Requires macOS 14 or newer and Xcode 16 or newer (or its Command Line Tools).

```bash
./build.sh            # builds build/Upline.app
./build.sh --install  # builds, copies to /Applications and launches
```

Look for the radar in your menu bar. Turn on **Launch at login** in Settings so the wake check runs every morning.

## Privacy

Upline never stores secret values. The scanner records env variable *names*, hostnames and package names. Everything stays on your Mac in `~/Library/Application Support/Upline/`. The only network traffic is to status pages, the services' own API hosts, and `captive.apple.com`, `1.1.1.1` and `8.8.8.8` for the "is it me" check.

## Add or fix a service

Create `~/Library/Application Support/Upline/catalog.json` with an array of entries. An entry with the same `id` as a built in one replaces it.

```json
[
  {
    "id": "acme",
    "name": "Acme Pay",
    "category": "payments",
    "statusPage": "https://status.acme.com",
    "probes": ["https://api.acme.com/health"],
    "packages": ["@acme/*"],
    "envKeys": ["ACME_"],
    "hosts": ["api.acme.com"],
    "images": [],
    "color": "#7C6CFF",
    "isCustom": false
  }
]
```

`statusFeed` is optional: `"statusio:<page id>"` for Status.io pages, a full RSS or Atom URL, or `"none"` to keep the status page as a link only.

## Project layout

```
Sources/Upline/
  App/   UplineApp (menu bar scene, app delegate, menu bar icon, windows)
  Core/  Models, Catalog, Scanner, StatusClient, Probes, System (FSEvents, wake, notifications), Store, Persistence
  UI/    Theme, RadarView, RootView, ListsView, ServiceDetailView, ProjectDetailView, OnboardingView, SettingsView
Resources/ Info.plist, AppIcon.png
build.sh
```
