# CHOSS

A social app for rock climbers, built around **places**. Follow your gym or your favorite
crag, and every send someone posts there (a video with grade, route name and description)
shows up in your feed. You can follow individual climbers too, Instagram-style.

## Features (MVP)

- **Home:** a feed of sends posted to places you follow plus climbers you follow, filterable by *All / Places / Climbers*. A row of your followed places sits at the top, like Instagram's stories tray.
- **Explore:** trending sends (filter by boulder/sport/trad/top-rope), popular gyms and crags, and a map of every place.
- **Search:** places, outdoor climbs, climbers, and sends (by route name, grade, place or caption).
- **Profile:** stats, hardest grades, a grid of sends, and followed places.
- **Place page:** follow button, follower/send/climber counts, map, sends at this place, and a *Post a send* button.
- **Crag profiles and climbs:** outdoor crags also have a *Climbs* tab listing their permanent routes and problems, grouped by area and searchable by name (typo-tolerant). Each climb has its own page with every video posted of it (beta, sortable by newest or most liked), its guidebook grade, the grade climbers say it feels like, and a *Post your send* button. When posting at a crag you search the crag's climbs and pick the best match, or add a missing one, so the video is filed under that climb.
- **Crag leaderboards:** a *Leaderboard* tab on every crag shows the top 3 places for **most climbs sent** (different climbs, so repeats don't count twice) and **hardest send** (with a Boulders / Routes toggle; Font is converted to V-scale and French to YDS so everyone is compared on one scale). Climbers who tie share a place, shown as a dropdown of their usernames.
- **Post a send:** pick or record a video, tag a gym or crag, choose discipline and send style (onsight/flash/send/repeat), and add a description. Two optional grades (V-scale, Font, YDS or French): the official **Grade** and your **Proposed Grade** ("feels like"). Untagged posts only reach your followers.
- **Video playback:** videos autoplay (looping) when mostly on screen and pause when scrolled away. Tap to pause, double-tap to like, and use the speaker button to mute or unmute (the setting is remembered). Sound plays even when the phone's silent switch is on, like other video apps. Tapping a video in a grid (profile, reposts, Explore) or a search result opens a scrollable feed that starts at that video.
- **Engagement:** likes (including double-tap on the video), comments (swipe to delete your own), and reposts. Reposts show up in your followers' feeds as "X reposted" and on a Reposts tab on your profile.
- **Direct messages:** the paper-plane button on a post opens *Send to*, which searches the people you follow with forgiving name matching (prefixes, initials, typos like "priay" → Priya). Pick one or more people, add a note, and send. The Messages inbox is the paper plane on Home.
- **Climber grade:** set a bouldering and/or rope grade or grade range (e.g. V4–V6, 5.11b–5.11d) in profile setup or *Edit profile*. You choose whether it shows on your profile.
- **Grades on thumbnails:** profile and Explore grids show each video's grade in the corner. The official grade is a filled pill and a proposed grade is an outlined "~V6". Nothing shows if neither was set.
- **Add a place:** users can add a missing gym or crag. It stays marked unverified until reviewed (see [docs/PLACES_DATA_STRATEGY.md](docs/PLACES_DATA_STRATEGY.md)).

## Running it

Requires **Xcode 16+** and iOS 17+.

1. Open `CHOSS.xcodeproj`.
2. Choose your team under *Signing & Capabilities* (or just run on a simulator).
3. Run. The app starts with sample data. Use the people icon on the Profile tab to switch between demo accounts, or choose *Create new account…* to go through profile setup.

The project uses Xcode's synchronized folders, so any file you add under `CHOSS/` is compiled automatically.

## Brand

The source logos live in `brand/`. `scripts/generate_brand_assets.py` (needs `pip install pillow numpy`) builds everything in the asset catalog from them:

- **AppIcon:** the hold icon, full-bleed 1024×1024.
- **Wordmark:** "CHOSS" in forest green, with a cream version for dark mode. Used as the Home header, the bottom-of-page footer, the splash screen, and profile setup.
- **HoldMark / HoldMarkLarge:** the hold shape alone, as a tintable image. Used for the Home tab button, the splash screen, and the empty feed.
- **Colors:** BrandGreen `#1D2A1E`, BrandCream `#F3EDE1`, the accent (forest green, lighter sage in dark mode), and OnAccent for text drawn on the accent.

If the logos change, replace the files in `brand/` and re-run the script.

## Architecture

```
CHOSS/
  CHOSSApp.swift              app entry, injects AppStore
  Models/                     User, Place, Post, Comment, Grade/GradeSystem/ClimbDiscipline/SendStyle
  Services/
    ClimbingRepository.swift  backend protocol (swap in Supabase/Firebase here)
    MockClimbingRepository    in-memory actor used today
    SampleData.swift          seed users, places, posts
  Store/AppStore.swift        @Observable state: feeds, follow graph, likes, search, optimistic updates
  Views/                      Home, Explore, Search, Profile, Places, Posts, Compose, Components
scripts/import_places.py      seed gyms (OpenStreetMap) and crags (OpenBeta)
docs/PLACES_DATA_STRATEGY.md  how to populate gyms and crags
```

Views only talk to `AppStore`, and `AppStore` only talks to `ClimbingRepository`. Moving
to a real backend means writing one new repository type.

## Next steps

1. A real backend (Supabase recommended; see the strategy doc) with auth, video upload and transcoding, and a paginated feed.
2. Seed places with `scripts/import_places.py` and add duplicate detection for user-added places.
3. Autoplaying muted video in the feed, push notifications ("3 new sends at Granite Works"), and gym owner accounts.
4. Tests for `AppStore` feed logic.
