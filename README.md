# Rasa Server
Trying to answer the age old question "What to watch tonight?"

## What is this?
A small companion docker app that sits next to Jellyfin and organizes your library by mood. It powers the RasaPlay app (where you actually browse/watch) and serves a minimal web UI for setup, sync, and tag editing.

- RasaPlay app: The viewing experience (separate app which is in WIP)
- Web UI: For setup, sync, tags

> [!IMPORTANT]
> This app is pretty much useless if you don't have jellyfin setup

## How it fits
- Runs alongside Jellyfin
- Keeps a local, mood‑tagged catalog
- Client app points at this server
- Web UI is for admins.

## What you do here (admin)
- Connect to Jellyfin and run syncs
- Add/remove mood tags on movies
- Optionally get auto‑tag suggestions (BYOK)
- Import/Export your tags map


## Mood buckets (Currently defined)
<details>
<summary> Mood list </summary>

- Dialogue-Driven
- Vibe Is the Plot
- Existential Core
- Crime, Grit & Style
- Men With Vibes (and Guns)
- Brainmelt Zone
- The Twist Is the Plot
- Slow Burn, Sharp Blade
- One-Room Pressure Cooker
- Emotional Gut Punch
- Psychological Pressure-Cooker
- Time Twists
- Visual Worship
- Obsidian Noir
- Rain & Neon Aesthetic
- Rainy Day Rewinds
- Ha Ha Ha
- Feel-Good Romance
- Coming of Age
- Late-Night Mind Rattle
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

</details>

## Quick start
- Docker (prebuilt image)
  1) Run this command
   ```
   docker pull ghcr.io/imgkl/rasaserver:latest && docker run -d --name rasa-server -p 3242:3242 \
         -v "$(pwd)/data:/app/data" \
         -v "$(pwd)/config:/app/config" \
         -v "$(pwd)/logs:/app/logs" \
         -e WEBUI_PORT=3242 \
         -e RASA_DATABASE_PATH=/app/data/rasa.sqlite \
         --restart unless-stopped ghcr.io/imgkl/rasaserver:latest
   ```
  2) Visit `http://localhost:3242`
  3) Complete Setup and run a Sync

- Local
  1) `./run.sh`
  2) Visit `http://localhost:8001`
  3) Complete Setup and Sync
  4) In the client app, set this server’s URL


## Roadmap

- [x] Jellyfin Integeration
- [x] Auto tagging using AI & Claude BYOK support (Optional)
- [x] Mood tagging
- [x] Import and Export of tagged movies 
- [x] Optional BYOK support for OMDb api to pull ratings from IMDb, Rotten Tomatoes and Metacritic.
- [ ] User Defined Tags
- [ ] More to be added, based on the requirements 


## Privacy
- Data stays local in `./data/rasa.sqlite`
- No accounts, no telemetry
- Auto‑tagging is optional and BYOK; only minimal movie context is sent if enabled

## Troubleshooting
- Web UI blank? Docker builds it; locally, `./run.sh` builds and starts it
- Setup loop? Check Jellyfin URL/credentials, then Sync
- Port busy? In Docker, change the host port in `docker-compose.yml`; locally, set `WEBUI_PORT`
