# CHOSS

A social app for rock climbers, built around **places**. Follow your gym or your favorite
crag, and every send someone posts there (a video with grade, route name and description)
shows up in your feed. You can follow individual climbers too, Instagram-style.

## Features (MVP)

- **Home:** one feed of your own sends, sends posted to places you follow, and posts (and reposts) from climbers you follow. A row of your followed places sits at the top, like Instagram's stories tray.
- **Explore:** trending sends (filter by boulder/sport/trad/top-rope/ice), popular gyms and crags, and a map of every place.
- **Search:** places, outdoor climbs, climbers, and sends (by route name, grade, place or caption). Searches run in the background on a prebuilt index (typo-tolerant, results in milliseconds even with hundreds of thousands of items), and long lists load 50 rows at a time. See [docs/SEARCH_AND_SCALE.md](docs/SEARCH_AND_SCALE.md).
- **Profile:** stats, up to 3 home gyms / crags, hardest grades, a grid of sends, and followed places. Tap Followers, Following or Places to see the list, with a forgiving search.
- **Place page:** follow button, follower/send/climber counts, map, sends at this place, and a *Post a send* button.
- **Crag profiles and climbs:** outdoor crags also have a *Climbs* tab listing their permanent routes and problems, grouped by area and searchable by name (typo-tolerant). Each climb has its own page with a grid of every video posted of it (beta, sortable by most recent or most liked; tap one to scroll through them from there), its guidebook grade, the grade climbers say it feels like, and a *Post your send* button. When posting at a crag you search the crag's climbs and pick the best match, or add a missing one, so the video is filed under that climb.
- **Crag leaderboards:** a *Leaderboard* tab on every crag shows the top 3 places for **most climbs sent** (different climbs, so repeats don't count twice) and **hardest send** (with a Boulders / Routes / Ice toggle; Font is converted to V-scale and French to YDS so everyone is compared on one scale; ice ranks by WI grade). Climbers who tie share a place, shown as a dropdown of their usernames.
- **Post a send:** pick or record a video, tag a gym or crag, pick the climb from a searchable list (the tagged crag's climbs, or every crag's climbs when no place is tagged, which then tags its crag) or add a new one; picking an existing climb fills in its discipline (and *Repeat* if you've sent it before). Only outdoor climbs have names for now: with a gym tagged, the climb name is greyed out. Choose discipline (boulder, sport, trad, top rope or ice) and style (onsight / flash / send / repeat / link), propose a grade (V-scale, Font, YDS, French, WI for water ice or M for mixed), and add a description. Scrolling dismisses the keyboard. Untagged posts only reach your followers.
- **Grades are community averages:** you don't set a climb's grade, you propose one. A climb's **Grade** is the average of everyone's proposed grades for it (the linked outdoor climb), falling back to the guidebook grade until someone proposes one. Links (sections, not full sends) don't count toward leaderboards or hardest sends.
- **Video playback:** videos autoplay (looping) when mostly on screen and pause when scrolled away. Tap to pause, double-tap to like (a bicep pops up and flexes, with a light haptic tap) or double-tap again to unlike, and use the speaker button to mute or unmute (the setting is remembered). Videos are capped at about half the screen's height (tall videos are cropped), so the author and the likes / comments stay visible while scrolling; the corner button opens the whole video full screen (swipe down or tap X to close). Sound plays even when the phone's silent switch is on, like other video apps. Tapping a video in a grid (profile, reposts, Explore) or a search result opens a scrollable feed that starts at that video.
- **Engagement:** likes (a flexed bicep; double-tap the video works too), comments (swipe to delete your own), and reposts. Reposts show up in your followers' feeds as "X reposted" and on a Reposts tab on your profile.
- **Profile pictures:** add, change or remove a photo in profile setup or *Edit profile*. After picking a photo you frame it: drag to center yourself and pinch to zoom inside a circle (double-tap resets). It's saved as a 600×600 image and shown everywhere avatars appear, with colored initials as the fallback.
- **Climber grade:** set a bouldering and/or rope grade or grade range (e.g. V4–V6, 5.11b–5.11d) in profile setup or *Edit profile*. You choose whether it shows on your profile. The *Hardest send* line (worked out from your posts) is optional too: turn it off in *Edit profile*.
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
- **Discipline icons:** hold (bouldering), quickdraw (sport), cam (trad) and top-rope anchor, cut from `brand/discipline-icons-source.png`, plus the ice axe from `brand/discipline-ice-source.png`, as tintable images (`DisciplineBoulder`, `…Sport`, `…Trad`, `…TopRope`, `…Ice`, plus `…Large`).
- **ExploreMark:** the boulderer-with-crash-pad figure from `brand/explore-icon-source.png` (label removed), used as the Explore tab icon.
- **FlexMark / FlexMarkFill:** the like button's flexed bicep (outline and filled), derived from `brand/flex-source.png` (the Noto Color Emoji "flexed biceps", Apache-2.0).
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
