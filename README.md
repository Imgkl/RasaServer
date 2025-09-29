# RasaServer

> [!NOTE]
**Answer "What should I watch tonight?" based on how you feel, not just by genre.**


RasaServer is a mood-first movie discovery layer that sits alongside Jellyfin, organizing your library into curated mood buckets. It powers the [RasaPlay](https://github.com/imgkl/RasaPlay) viewing app and includes a web UI for setup and tag management.

---

## Why RasaServer?

**The Problem:** Browsing by genre doesn't match how you actually choose movies. "Action" doesn't tell you if it's a brainless popcorn flick or a slow-burn thriller.

**The Solution:** Mood-based organization. Instead of "Thriller," you browse:
- 🎭 **Dialogue-Driven** - Character-focused narratives
- 🌧️ **Rain & Neon Aesthetic** - Cyberpunk/neo-noir vibes  
- 🧠 **Brainmelt Zone** - Mind-bending psychological films
- 😂 **Ha Ha Ha** - Pure comedy, no drama

**36 curated moods** (expandable) that actually answer "what matches my vibe right now?"

---

## Architecture
```
┌──────────────┐
│   Jellyfin   │ ← Your existing media server (source of truth)
└──────┬───────┘
       │ webhooks (real-time sync)
       ▼
┌──────────────────────────┐
│     RasaServer           │ ← Mood tagging + transformation layer
│  ┌────────────────────┐  │
│  │ Web UI (Admin)     │  │ ← Setup, sync, manual / automatic tagging
│  └────────────────────┘  │
│  ┌────────────────────┐  │
│  │ REST API           │  │ ← Powers client apps
│  └────────────────────┘  │
└──────────┬───────────────┘
           │ API
           ▼
    ┌──────────────┐
    │  RasaPlay    │ ← Client app (browse by mood, watch)
    └──────────────┘
```

**How it works:**
1. RasaServer syncs your Jellyfin library (one-time setup via Web UI)
2. Automatically tags movies into mood buckets
3. Stays in sync via Jellyfin webhooks (real-time updates)
4. Web UI for admin tasks: configuration, manual tagging, sync management
5. RasaPlay app (or any client) queries RasaServer API for mood-organized content

---

## Features

### Core
- ✅ **Mood-based organization** - 36 curated moods (see full list below)
- ✅ **Real-time sync** - Jellyfin webhooks keep data fresh
- ✅ **Auto-tagging** - Optional AI suggestions (BYOK: Claude)
- ✅ **Manual tagging** - Web UI for fine-tuning
- ✅ **Import/Export** - Backup your mood mappings
- ✅ **External ratings** - Optional OMDB integration (IMDb, RT, Metacritic)
- ✅ **Built-in Web UI** - No separate admin tools needed

### Privacy
- 🔒 **Local-first** - All data in `./data/rasa.sqlite`
- 🔒 **No telemetry** - Zero tracking, no accounts
- 🔒 **BYOK only** - AI tagging requires your own API key (optional)

---

## Quick Start

### Option 1: Docker (Recommended)
```bash
docker run -d --name rasa-server -p 3242:3242 \
  -v "$(pwd)/data:/app/data" \
  -v "$(pwd)/config:/app/config" \
  -v "$(pwd)/logs:/app/logs" \
  -e WEBUI_PORT=3242 \
  -e RASA_DATABASE_PATH=/app/data/rasa.sqlite \
  --restart unless-stopped \
  ghcr.io/imgkl/rasaserver:latest
```

Then:
1. Open `http://localhost:3242` in your browser (Web UI)
2. Complete setup wizard (enter Jellyfin URL + credentials)
3. Run initial sync

### Option 2: Local Development
```bash
git clone https://github.com/imgkl/RasaServer
cd RasaServer
./run.sh
```

Web UI: `http://localhost:8001`

---
## Mood Buckets (36 Total)

<details>
<summary>Click to expand full mood list</summary>

### Character & Dialogue
- Dialogue-Driven
- Vibe Is the Plot
- Existential Core
- Antihero Study
- Ensemble Mosaic

### Crime & Noir
- Crime, Grit & Style
- Men With Vibes (and Guns)
- Obsidian Noir
- Rain & Neon Aesthetic
- Cat and Mouse

### Psychological
- Brainmelt Zone
- The Twist Is the Plot
- Psychological Pressure-Cooker
- Late-Night Mind Rattle
- Uncanny Vibes

### Atmosphere
- Slow Burn, Sharp Blade
- One-Room Pressure Cooker
- Visual Worship
- Rainy Day Rewinds
- Quiet Epics

### Emotional
- Emotional Gut Punch
- Feel-Good Romance
- Coming of Age
- Bittersweet Aftermath

### Genre-Specific
- Ha Ha Ha (Comedy)
- Horror & Unease
- Heist Energy
- Time Twists

### Curated Collections
- Film School Shelf
- Modern Masterpieces
- Regional Gems
- Underseen Treasures
- Based on Vibes (True Story)
- Cult Chaos
- Experimental Cinema
- WTF Did I Watch

</details>

---

## Web UI Features

Access at `http://your-server:3242`

- **Setup Wizard** - Initial Jellyfin connection configuration
- **Sync Management** - Manual sync, view sync status and history
- **Movie Browser** - View all movies with their current mood tags
- **Tag Editor** - Add/remove mood tags from individual movies
- **AI Auto-Tag** - Bulk suggestions for untagged movies (requires Claude API key)
- **Import/Export** - Backup and restore your mood mappings
- **Settings** - Configure integrations (OMDB, Claude API)

---
## Roadmap

- [x] Jellyfin integration
- [x] Mood tagging system
- [x] Real-time webhook sync
- [x] Web UI for admin tasks
- [x] AI auto-tagging (BYOK: Claude)
- [x] Import/Export mood mappings
- [x] OMDB ratings integration (BYOK)
- [ ] User-defined custom moods
- [ ] Multi-user support
- [ ] Advanced filtering (combine moods, exclude tags)
- [ ] Mood analytics (most-watched moods, etc.)

---

## Contributing

This is a personal project, but PRs are welcome for:
- Bug fixes
- New mood definitions (with clear criteria)
- Performance improvements
- Web UI enhancements

Please open an issue first to discuss major changes.

---

## License

MIT - Use it, fork it, modify it. Just don't blame me if your movie night goes wrong.

---

## Credits

Built to solve a personal problem: "I have 500 movies but can't decide what to watch."

Inspired by the realization that mood > genre for actually picking movies.
