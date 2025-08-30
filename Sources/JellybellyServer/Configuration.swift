import Foundation
import Yams
import Logging

final class JellybellyConfiguration: @unchecked Sendable {
    // Server Settings
    var host: String = "0.0.0.0"
    var port: Int = 8001
    
    // Jellyfin Connection
    var jellyfinUrl: String = "http://192.168.0.111:8097"
    var jellyfinApiKey: String = ""
    var jellyfinUserId: String = ""
    
    // Database
    var databasePath: String = "jellybelly.sqlite"
    
    // BYOK - Bring Your Own Key (Optional)
    var anthropicApiKey: String? = nil
    
    // Auto-tagging settings
    var enableAutoTagging: Bool = false
    var maxAutoTags: Int = 5
    var autoTaggingPrompt: String = """
    Based on this movie's metadata, suggest up to 4 mood tags from the available list.
    Consider the movie's genre, director style, themes, and overall vibe.
    Only return tags that exist in the provided mood buckets list.
    """
    
    // Guiding principle:
    // - These buckets are “primary mood lenses,” not rigid genres.
    // - Overlaps happen; a film can live in multiple buckets if the mood strongly fits.
    // - When in doubt, pick the bucket that best describes how the film feels while watching.
    let moodBuckets: [String: MoodBucket] = [
        "dialogue-driven": MoodBucket(
            title: "Dialogue-Driven",
            description: """
Word, rhythm, and subtext carry the drama; the camera often gives breathing room for talk to spark tension, humor, or revelation. Watchable like great theatre—lingering beats, reversals inside conversations, and characters weaponizing language.
""",
            tags: ["talky","verbal-sparring","subtext","character-focus","theatrical","intimate","witty","philosophical"]
        ),
        "vibe-is-the-plot": MoodBucket(
            title: "Vibe Is the Plot",
            description: """
Story beats recede so mood, texture, and rhythm can lead; the film invites you to drift rather than decode. Momentum comes from tone—music, color, and pacing—more than conventional conflict.
""",
            tags: ["ambient","mood-first","dreamy","meandering","hypnotic","texture","tone-poem"]
        ),
        "existential-core": MoodBucket(
            title: "Existential Core",
            description: """
Meditations on meaning, mortality, and identity—characters wrestle with purpose against an indifferent or absurd world. Expect quiet rupture, searching monologues, and choices that reverberate beyond plot mechanics.
""",
            tags: ["meaning-of-life","identity","mortality","introspective","philosophical","alienation","melancholy"]
        ),
        "crime-grit-style": MoodBucket(
            title: "Crime, Grit & Style",
            description: """
Underworld stakes rendered with flair—slick craft meets bruised morality. Choreography, cutting, and design elevate the grime; the rush comes from cool surfaces clashing with messy consequence.
""",
            tags: ["crime","stylish","gritty","underworld","moral-ambiguity","adrenaline","setpieces"]
        ),
        "men-with-vibes": MoodBucket(
            title: "Men With Vibes (and Guns)",
            description: """
Charisma, restraint, and coiled menace—stoic leads who command the frame with minimal words. The tension lives in posture, glances, and ritualistic competence punctuated by sudden violence.
""",
            tags: ["stoic","cool-factor","aura","competence-porn","minimalist-dialogue","menace","iconic"]
        ),
        "brainmelt-zone": MoodBucket(
            title: "Brainmelt Zone",
            description: """
Films that fracture perception—memory slips, unreliable frames, and shifting truths. You’re meant to feel disoriented, then delighted, when pieces reassemble into a new picture.
""",
            tags: ["surreal","unreliable","identity-blur","puzzle-box","dream-logic","metafiction","mind-bending"]
        ),
        "the-twist-is-the-plot": MoodBucket(
            title: "The Twist Is the Plot",
            description: """
Carefully engineered reveals that force a re-read of earlier scenes. Clues, misdirection, and set-ups are the architecture; satisfaction comes when the trapdoor opens and the story reframes.
""",
            tags: ["twist","reveal-driven","misdirection","breadcrumbs","whodunit-energy","recontextualization"]
        ),
        "slow-burn-sharp-blade": MoodBucket(
            title: "Slow Burn, Sharp Blade",
            description: """
Patient escalation with an exacting payoff—quiet stakes accumulate until a precise, surgical release. The pleasure is in simmering pressure and the craft that keeps you leaning forward.
""",
            tags: ["patient","tension-build","minimalism","precision","escalation","payoff","discipline"]
        ),
        "one-room-pressure-cooker": MoodBucket(
            title: "One-Room Pressure Cooker",
            description: """
Constrained space, maximal tension—logistics, power dynamics, and blocking do the heavy lifting. The room itself becomes the chessboard as alliances shift and time tightens.
""",
            tags: ["single-location","claustrophobia","real-time-ish","logistical-tension","ensemble-dynamics","containment"]
        ),
        "emotional-gut-punch": MoodBucket(
            title: "Emotional Gut Punch",
            description: """
The tension is primarily psychological, with characters grappling with their own demons or external pressures. The setting may be a single room, but the stakes are internal, with characters struggling to maintain their sanity or relationships.
""",
            tags: ["emotional-tension","mental-unraveling","obsession","gaslighting","subjective-reality","anxiety","emotional-impact"]
        ),
        "psychological-pressure-cooker": MoodBucket(
            title: "Psychological Pressure-Cooker",
            description: """
Paranoia and inner fracture create the squeeze; dread comes from minds under siege, not just walls closing in. Gaslighting, obsession, and unraveling perception drive the stakes.
""",
            tags: ["paranoia","obsession","gaslighting","mental-unraveling","subjective-reality","anxiety"]
        ),
        "time-twists": MoodBucket(
            title: "Time Twists",
            description: """
Loops, leaps, and braided timelines shape the experience—cause and effect become toys. The thrill is logical play: paradoxes, resets, and decisions echoing across alternate tracks.
""",
            tags: ["time-loop","paradox","nonlinear","alternate-timelines","butterfly-effect","chronological-puzzle"]
        ),
        "visual-worship": MoodBucket(
            title: "Visual Worship",
            description: """
Every frame is composed like a poster—camera, color, and light do the storytelling. You watch for images that linger: painterly blocking, graphic silhouettes, and deliberate motion.
""",
            tags: ["painterly","auteur-visuals","composed-frames","color-theory","cinematography-first","tableau"]
        ),
        "obsidian-noir": MoodBucket(
            title: "Obsidian Noir",
            description: """
Modern noir bathed in inky contrast—sleek surfaces, moral fog, and fatalistic momentum. Desire and consequence spiral in shadows where style sharpens the sting.
""",
            tags: ["noir","shadows","fatalism","moral-fog","sleek","hardboiled","cynicism"]
        ),
        "rain-neon-aesthetic": MoodBucket(
            title: "Rain & Neon Aesthetic",
            description: """
Wet streets and synth glow—urban melancholy with reflective textures. The city hums like a mood board as color, signage, and rain-sheen turn movement into music.
""",
            tags: ["neon","rain-sheen","urban-melancholy","synth","nightscape","futuristic","reflective"]
        ),
        "rainy-day-rewinds": MoodBucket(
            title: "Rainy Day Rewinds",
            description: """
Comfort cinema—warm rhythms, friendly stakes, and lines you love saying with the characters. Rewatchable by design, delivering soft catharsis rather than high drama.
""",
            tags: ["cozy","nostalgic","warmth","comfort-watch","low-stakes","feelgood","rewatchable"]
        ),
        "ha-ha-ha": MoodBucket(
            title: "Ha Ha Ha",
            description: """
Built for laughs—timing, chemistry, and set-ups that snap. Whether sharp wit or joyful silliness, the priority is rhythmic comedy that lands on the beat.
""",
            tags: ["comedy","wit","banter","screwball","situational","parody","physical-comedy"]
        ),
        "feel-good-romance": MoodBucket(
            title: "Feel-Good Romance",
            description: """
Tender arcs that leave a glow—connection, vulnerability, and earned joy. Stakes are emotional rather than catastrophic; the charm is in small choices that open hearts.
""",
            tags: ["tender","uplifting","chemistry","hopeful","heartwarming","meet-cute","healing"]
        ),
        "coming-of-age": MoodBucket(
            title: "Coming of Age",
            description: """
Transitions and firsts—the ache and thrill of becoming. Identity coalesces through mistakes, friendships, and moments that feel bigger than they look on paper.
""",
            tags: ["youth","self-discovery","first-love","growing-pains","rites-of-passage","nostalgia"]
        ),
        "late-night-mind-rattle": MoodBucket(
            title: "Late-Night Mind Rattle",
            description: """
Films that echo at 1:47 a.m.—eerie, thoughtful, and a little unmooring. Not pure horror or puzzle boxes, but lingering ideas that won’t let you sleep just yet.
""",
            tags: ["haunting","liminal","restless-thoughts","afterglow","uneasy-calm","philosophical-chill"]
        ),
        "uncanny-vibes": MoodBucket(
            title: "Uncanny Vibes",
            description: """
Slightly off reality—dreamlike cadence, ritual behavior, or settings that feel familiar yet wrong. The strangeness is gentle but persistent, like déjà vu you can’t shake.
""",
            tags: ["uncanny","liminal","dreamlike","off-kilter","estrangement","eeriness","surreal-lite"]
        ),
        "horror-and-unease": MoodBucket(
            title: "Horror & Unease",
            description: """
Dread-forward storytelling—menace in tone, image, and implication. Scares may be quiet or loud, but the throughline is anxiety riding beside you to the credits.
""",
            tags: ["dread","terror","suspense","atmospheric","disturbing","fear","nightmare"]
        ),
        "wtf-did-i-watch": MoodBucket(
            title: "WTF Did I Watch",
            description: """
Transgressive, absurd, or confrontational—cinema that breaks decorum and dares you to keep up. You might regret it, but you won’t forget it.
""",
            tags: ["transgressive","absurd","shock","provocative","boundary-pushing","cult-energy"]
        ),
        "film-school-shelf": MoodBucket(
            title: "Film School Shelf",
            description: """
Canonical essentials that map the medium’s language. Historically pivotal works—form, editing, performance—that every cinephile benefits from knowing cold.
""",
            tags: ["canon","foundational","history","form-defining","influential","curriculum"]
        ),
        "modern-masterpieces": MoodBucket(
            title: "Modern Masterpieces",
            description: """
2000s+ pinnacles where craft, ambition, and resonance align. Acclaim isn’t the point—enduring impact is, the kind that sets a bar for the era.
""",
            tags: ["contemporary-classic","acclaimed","ambitious","craft-excellence","enduring"]
        ),
        "regional-gems": MoodBucket(
            title: "Regional Gems",
            description: """
            Standout works from the language of the land. If you want to see a movie from a specific language, this is must-see.
            """,
            tags: ["local-texture","authenticity","language-of-the-land"]
        ),
        "underseen-treasures": MoodBucket(
            title: "Underseen Treasures",
            description: """
Overlooked gems that reward discovery—maybe distribution failed them, maybe marketing did. Championing these expands the canon in meaningful ways.
""",
            tags: ["hidden-gem","underrated","festival-darling","niche","word-of-mouth","cult-potential"]
        ),
        "heist-energy": MoodBucket(
            title: "Heist Energy",
            description: """
Clever planning, double-crosses, and the kinetic pleasure of competence under a clock. The joy is in mechanism: teams, roles, and the moment when the plan meets chaos.
""",
            tags: ["caper","planning","team-dynamics","setpiece-machinery","betrayal","ticking-clock","adrenaline"]
        ),
        "cat-and-mouse": MoodBucket(
            title: "Cat and Mouse",
            description: """
Predator and prey locked in a strategic duel—near-misses, traps, and reversals. Momentum swings as each side adapts, escalating tension without needing huge setpieces.
""",
            tags: ["pursuit","duel","strategy","tension-swings","near-miss","trap-laying","escalation"]
        ),
        "antihero-study": MoodBucket(
            title: "Antihero Study",
            description: """
Magnetic, flawed leads bending morality to the breaking point. The draw is intimacy with contradiction—charm and damage, empathy and recoil.
""",
            tags: ["moral-ambiguity","character-study","flawed-protagonist","charisma","downfall","complicity"]
        ),
        "ensemble-mosaic": MoodBucket(
            title: "Ensemble Mosaic",
            description: """
Interlocking characters and perspectives forming a larger pattern. Structure, rhythm, and cross-cut empathy do the lifting as stories harmonize.
""",
            tags: ["ensemble","interwoven","multi-perspective","cross-cutting","network-narrative","choral"]
        ),
        "quiet-epics": MoodBucket(
            title: "Quiet Epics",
            description: """
Large stakes told with restraint—time, landscape, or history scaled down to intimate human beats. You feel immensity without bombast.
""",
            tags: ["sweeping-intimacy","landscape","time-scale","measured","austere","contemplative","subtle-grandness"]
        ),
        "bittersweet-aftermath": MoodBucket(
            title: "Bittersweet Aftermath",
            description: """
Endings that ache softly—loss braided with grace, acceptance, or a small light left on. It’s not happy or tragic; it’s human.
""",
            tags: ["bittersweet","melancholy","closure","grace","acceptance","quiet-cry"]
        ),
        "based-on-vibes-true-story": MoodBucket(
            title: "Based on Vibes (True Story)",
            description: """
Fact-rooted stories that privilege mood over transcript accuracy. The truth is emotional: tone, place, and lived texture over courtroom exactness.
""",
            tags: ["true-story","based-on-real-events","tone-forward","impressionistic","period-texture","biographical-vibes"]
        ),
        "cult-chaos": MoodBucket(
            title: "Cult Chaos",
            description: """
Bizarre favorites that inspire obsession—quotable, midnight-movie energy, and scenes that live rent-free. Imperfect by design; unforgettable by effect.
""",
            tags: ["cult","midnight-movie","quotable","weird-core","obsession","outsider-charm"]
        ),
        "experimental-cinema": MoodBucket(
            title: "Experimental Cinema",
            description: """
Form-first filmmaking—structure, sound, or image pushed into new shapes. Narrative may be minimal or absent; discovery happens through sensation and pattern.
""",
            tags: ["avant-garde","form-forward","non-narrative","sound-design","structure-play","provocation","art-house"]
        )
    ]

    init() {}
    
    static func load(from path: String = "config.yaml") throws -> JellybellyConfiguration {
        let config = JellybellyConfiguration()
        
        // Check if config file exists
        guard FileManager.default.fileExists(atPath: path) else {
            // Create default config file
            try config.save(to: path)
            print("📝 Created default config at \(path)")
            return config
        }
        
        // Load from file
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let yaml = try Yams.load(yaml: String(data: data, encoding: .utf8) ?? "")
        
        if let dict = yaml as? [String: Any] {
            config.host = dict["host"] as? String ?? config.host
            config.port = dict["port"] as? Int ?? config.port
            config.jellyfinUrl = dict["jellyfin_url"] as? String ?? config.jellyfinUrl
            config.jellyfinApiKey = dict["jellyfin_api_key"] as? String ?? config.jellyfinApiKey
            config.jellyfinUserId = dict["jellyfin_user_id"] as? String ?? config.jellyfinUserId
            config.databasePath = dict["database_path"] as? String ?? config.databasePath
            config.anthropicApiKey = dict["anthropic_api_key"] as? String
            config.enableAutoTagging = dict["enable_auto_tagging"] as? Bool ?? config.enableAutoTagging
            config.maxAutoTags = dict["max_auto_tags"] as? Int ?? config.maxAutoTags
            config.autoTaggingPrompt = dict["auto_tagging_prompt"] as? String ?? config.autoTaggingPrompt
        }

        // Fallback to environment variable if not set in file
        if (config.anthropicApiKey == nil || config.anthropicApiKey?.isEmpty == true),
           let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            config.anthropicApiKey = envKey
        }
        
        return config
    }
    
    func save(to path: String = "config.yaml") throws {
        let base: [String: Any] = [
            "# Jellybelly Server Configuration": "",
            "# Server settings": "",
            "host": host,
            "port": port,
            "": "",
            "# Jellyfin connection": "",
            "jellyfin_url": jellyfinUrl,
            "jellyfin_api_key": jellyfinApiKey,
            "jellyfin_user_id": jellyfinUserId,
            " ": "",
            "# Database": "",
            "database_path": databasePath,
            "  ": "",
            "# BYOK - Optional API Keys": "",
            "# anthropic_api_key": "sk-ant-...", 
            "   ": "",
            "# Auto-tagging (requires API key)": "",
            "enable_auto_tagging": enableAutoTagging,
            "max_auto_tags": maxAutoTags,
            "auto_tagging_prompt": autoTaggingPrompt
        ]
        
        // Persist anthropic key if present
        var out = base
        if let key = anthropicApiKey, !key.isEmpty { out["anthropic_api_key"] = key }
        let yaml = try Yams.dump(object: out)
        try yaml.write(to: URL(fileURLWithPath: path), atomically: true, encoding: String.Encoding.utf8)
    }
}

struct MoodBucket: Codable, Sendable {
    let title: String
    let description: String
    let tags: [String]?
}

extension MoodBucket {
    init(title: String, description: String) {
        self.title = title
        self.description = description
        self.tags = nil
    }
}

struct MoodBucketsResponse: Codable, Sendable {
    let moods: [String: MoodBucket]
}
