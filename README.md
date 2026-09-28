# CHOSS

A social app for rock climbers, built around **places**. Follow your gym or your favorite
crag, and every send someone posts there (a video with grade, route name and description)
shows up in your feed. You can follow individual climbers too, Instagram-style.

## Features (MVP)

- **Home:** a feed of sends posted to places you follow plus climbers you follow, filterable by *All / Places / Climbers*. A row of your followed places sits at the top, like Instagram's stories tray.
- **Explore:** trending sends (filter by boulder/sport/trad/top-rope), popular gyms and crags, and a map of every place.
- **Search:** places, climbers, and sends (by route name, grade, place or caption).
- **Profile:** stats, hardest grades, a grid of sends, and followed places.
- **Place page:** follow button, follower/send/climber counts, map, sends at this place, and a *Post a send* button.
- **Post a send:** pick or record a video, tag a gym or crag, choose discipline and grade (V-scale, Font, YDS, French), pick the send style (onsight/flash/send/repeat), and add a description. Untagged posts only reach your followers.
- **Engagement:** likes (including double-tap on the video), comments, and sharing.
- **Add a place:** users can add a missing gym or crag. It stays marked unverified until reviewed (see [docs/PLACES_DATA_STRATEGY.md](docs/PLACES_DATA_STRATEGY.md)).

## Running it

Requires **Xcode 16+** and iOS 17+.

1. Open `CHOSS.xcodeproj`.
2. Choose your team under *Signing & Capabilities* (or just run on a simulator).
3. Run. The app starts with sample data. Use the people icon on the Profile tab to switch between demo accounts and see the feed from different climbers' points of view.

The project uses Xcode's synchronized folders, so any file you add under `CHOSS/` is compiled automatically.

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
