# JellyBelly Server

Pick a movie by mood, not metadata.

## What is this?
JellyBelly Server sits next to Jellyfin and sorts your library by mood. It powers the JellyBelly tvOS app (where you browse and watch) and includes a small web UI for setup, sync, and tag management.

- tvOS app: the watching experience (separate app)
- Web UI (bundled here): admin tool for setup, syncing, and tags

## Why use it?
Finding “the right thing tonight” is easier by vibe. JellyBelly gives you a clear mood language and quick tagging so your tvOS app can surface films that feel right now.

## What you get (server / admin)
- Curated mood taxonomy out of the box
- Tag movies with mood buckets
- Sync with Jellyfin (library + watched state)
- Optional auto‑tag suggestions (BYOK)
- Import/Export your tags map
- HTTP API for moods, movies, tags, search, sync, settings

## Predefined mood buckets
A sample of the built‑ins:
- Dialogue‑Driven
- Vibe Is the Plot
- Existential Core
- Crime, Grit & Style
- Men With Vibes (and Guns)
- Brainmelt Zone
- The Twist Is the Plot
- Slow Burn, Sharp Blade
- One‑Room Pressure Cooker
- Psychological Pressure‑Cooker
- Time Twists
- Visual Worship
- Obsidian Noir
- Rain & Neon Aesthetic
- Rainy Day Rewinds
- Feel‑Good Romance
- Coming of Age
- Late‑Night Mind Rattle
- Uncanny Vibes
- Horror & Unease
- WTF Did I Watch
- Film School Shelf
- Modern Masterpieces
- Regional Gems
- Underseen Treasures
- Heist Energy
- Cat and Mouse
- Antihero Study
- Ensemble Mosaic
- Quiet Epics
- Bittersweet Aftermath
- Based on Vibes (True Story)
- Cult Chaos
- Experimental Cinema

See the full list under Moods in the web UI.

## How it fits together
- Server runs alongside Jellyfin and keeps a local, mood‑tagged catalog
- tvOS app connects to this server (that’s where people browse/watch)
- Web UI is for admins only: setup, sync, and tags

## Quick start
- Docker
  1) `docker compose up -d`
  2) Visit `http://localhost:3242`
  3) Complete Setup and run a Sync
  4) Open the tvOS app and point it at your server URL

- Local
  1) `./run.sh`
  2) Visit `http://localhost:8001`
  3) Complete Setup and Sync
  4) Open the tvOS app and point it at your server URL

If you’re redirected to `/setup`, finish the wizard first.

## Privacy & data
- Data lives locally in `./data/jellybelly.sqlite`
- No accounts, no telemetry
- Auto‑tagging is optional and BYOK; only minimal movie context is sent if enabled

## Admin web UI
- Open the server URL in a browser
- Use Setup to connect to Jellyfin, then run Sync
- Adjust tags in Moods/Tags; changes reflect in the tvOS app

## Troubleshooting
- Web UI won’t load? Docker builds it for you; locally, `./run.sh` does
- Stuck on setup? Revisit `/setup`, verify Jellyfin URL/credentials, then Sync
- Port busy? In Docker, change the left side in `docker-compose.yml`; locally, set `WEBUI_PORT`

## Questions
Open an issue or discussion with what you’re trying to do. A short clip or screenshot helps.
