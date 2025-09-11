# Rasa Server

Pick a movie by mood.

## What is this?
A small server that sits next to Jellyfin and organizes your library by mood. It powers the tvOS app (where you actually browse/watch) and serves a minimal web UI for setup, sync, and tag editing.

- tvOS app: the viewing experience (separate app)
- Web UI: admin only (setup, sync, tags)

## How it fits
- Runs alongside Jellyfin
- Keeps a local, mood‑tagged catalog
- tvOS app points at this server
- Web UI is for admins, not viewers

## What you do here (admin)
- Connect to Jellyfin and run syncs
- Add/remove mood tags on movies
- Optionally get auto‑tag suggestions (BYOK)
- Import/Export your tags map

## Mood buckets (sample)
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

See the full list under Moods in the web UI.

## Quick start
- Docker
  1) `docker compose up -d`
  2) Visit `http://localhost:3242`
  3) Complete Setup and run a Sync
  4) In the tvOS app, set this server’s URL

- Local
  1) `./run.sh`
  2) Visit `http://localhost:8001`
  3) Complete Setup and Sync
  4) In the tvOS app, set this server’s URL

If you’re redirected to `/setup`, finish the wizard first.

## Privacy
- Data stays local in `./data/rasa.sqlite`
- No accounts, no telemetry
- Auto‑tagging is optional and BYOK; only minimal movie context is sent if enabled

## Troubleshooting
- Web UI blank? Docker builds it; locally, `./run.sh` builds and starts it
- Setup loop? Check Jellyfin URL/credentials, then Sync
- Port busy? In Docker, change the host port in `docker-compose.yml`; locally, set `WEBUI_PORT`
