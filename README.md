# CHOSS

A social app for rock climbers, built around **places**. Follow your gym or your favorite
crag, and every send someone posts there (a video with grade, route name and description)
shows up in your feed. You can follow individual climbers too, Instagram-style.

## Features (MVP)

- **Home:** a feed of sends posted to places you follow plus climbers you follow, filterable by *All / Places / Climbers*. A row of your followed places sits at the top, like Instagram's stories tray.
- **Explore:** trending sends (filter by boulder/sport/trad/top-rope), popular gyms and crags, and a map of every place.
- **Search:** places, outdoor climbs, climbers, and sends (by route name, grade, place or caption). Searches run in the background on a prebuilt index (typo-tolerant, results in milliseconds even with hundreds of thousands of items), and long lists load 50 rows at a time. See [docs/SEARCH_AND_SCALE.md](docs/SEARCH_AND_SCALE.md).
- **Profile:** stats, up to 3 home gyms / crags, hardest grades, a grid of sends, and followed places. Tap Followers, Following or Places to see the list, with a forgiving search.
- **Place page:** follow button, follower/send/climber counts, map, sends at this place, and a *Post a send* button.
- **Crag profiles and climbs:** outdoor crags also have a *Climbs* tab listing their permanent routes and problems, grouped by area and searchable by name (typo-tolerant). Each climb has its own page with a grid of every video posted of it (beta, sortable by most recent or most liked; tap one to scroll through them from there), its guidebook grade, the grade climbers say it feels like, and a *Post your send* button. When posting at a crag you search the crag's climbs and pick the best match, or add a missing one, so the video is filed under that climb.
- **Crag leaderboards:** a *Leaderboard* tab on every crag shows the top 3 places for **most climbs sent** (different climbs, so repeats don't count twice) and **hardest send** (with a Boulders / Routes toggle; Font is converted to V-scale and French to YDS so everyone is compared on one scale). Climbers who tie share a place, shown as a dropdown of their usernames.
- **Post a send:** pick or record a video, tag a gym or crag, pick the climb from a searchable list (the crag's climbs, or routes already posted at the gym) or add a new one; picking an existing climb fills in its discipline (and *Repeat* if you've sent it before). Choose discipline and style (onsight / flash / send / repeat / link), propose a grade (V-scale, Font, YDS or French), and add a description. Scrolling dismisses the keyboard. Untagged posts only reach your followers.
- **Grades are community averages:** you don't set a climb's grade, you propose one. A climb's **Grade** is the average of everyone's proposed grades for it (the linked outdoor climb, or the same route name at the same gym), falling back to the guidebook grade until someone proposes one. Links (sections, not full sends) don't count toward leaderboards or hardest sends.
- **Video playback:** videos autoplay (looping) when mostly on screen and pause when scrolled away. Tap to pause, double-tap to like, and use the speaker button to mute or unmute (the setting is remembered). Sound plays even when the phone's silent switch is on, like other video apps. Tapping a video in a grid (profile, reposts, Explore) or a search result opens a scrollable feed that starts at that video.
- **Engagement:** likes (including double-tap on the video), comments (swipe to delete your own), and reposts. Reposts show up in your followers' feeds as "X reposted" and on a Reposts tab on your profile.
- **Direct messages:** the paper-plane button on a post opens *Send to*, which searches the people you follow with forgiving name matching (prefixes, initials, typos like "priay" → Priya). Pick one or more people, add a note, and send. The Messages inbox is the paper plane on Home.
- **Profile pictures:** add, change or remove a photo in profile setup or *Edit profile*. After picking a photo you frame it: drag to center yourself and pinch to zoom inside a circle (double-tap resets). It's saved as a 600×600 image and shown everywhere avatars appear, with colored initials as the fallback.
- **Climber grade:** set a bouldering and/or rope grade or grade range (e.g. V4–V6, 5.11b–5.11d) in profile setup or *Edit profile*. You choose whether it shows on your profile.
- **Grades on thumbnails:** profile and Explore grids show each climb's grade (the community average) in the corner, when it has one.
- **US gym and crag directories:** 1,535 US climbing gyms (including university, YMCA and rec-center walls) and 2,128 outdoor climbing areas are built in, each with its nearest town and state, so they're searchable by name or town and appear on the Explore map. Crags are tagged bouldering, rope (sport/trad) or both. Sources: `data/US_Climbing_Gyms_Simple.xlsx` → `scripts/import_gyms_xlsx.py`, and `data/US_Climbing_Areas.xlsx` → `scripts/import_crags_xlsx.py`.
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
- **Discipline icons:** hold (bouldering), quickdraw (sport), cam (trad) and top-rope anchor, cut from `brand/discipline-icons-source.png` into tintable images (`DisciplineBoulder`, `…Sport`, `…Trad`, `…TopRope`, plus `…Large`).
- **ExploreMark:** the boulderer-with-crash-pad figure from `brand/explore-icon-source.png` (label removed), used as the Explore tab icon.
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
docs/SEARCH_AND_SCALE.md      search index, lookups, and scaling past the device
```

Views only talk to `AppStore`, and `AppStore` only talks to `ClimbingRepository`. Moving
to a real backend means writing one new repository type.

## Next steps

1. A real backend (Supabase recommended; see the strategy doc) with auth, video upload and transcoding, and a paginated feed.
2. Seed places with `scripts/import_places.py` and add duplicate detection for user-added places.
3. Autoplaying muted video in the feed, push notifications ("3 new sends at Movement Gowanus"), and gym owner accounts.
4. Tests for `AppStore` feed logic.
