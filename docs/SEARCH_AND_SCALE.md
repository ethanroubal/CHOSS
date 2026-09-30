# Search and scale

Search got slow once 3,600+ real gyms and crags were bundled. Each keystroke ran the full
typo-tolerant matcher over every place on the main thread (twice: once for the list, once for
the "no results" check), and list rows counted sends by scanning every post. This doc explains
how it works now and what changes when data outgrows the phone.

## What happens on a keystroke

1. **Debounce.** `runSearch` (Views/Components/SearchSupport.swift) waits 120 ms. A new
   keystroke cancels the pending search, so fast typing doesn't queue work.
2. **Off the main thread.** `AppStore.searchPlaceIDs` / `searchClimbIDs` / `searchUserIDs`
   run on a snapshot of a `SearchIndex` in a background task and return ids.
   The previous results stay on screen until the new ones land.
3. **Bounded candidates.** `SearchIndex` (Services/SearchIndex.swift) never scores every item:
   - words starting with what you typed (and initials like "ml") come from a binary search in a
     sorted word list;
   - 3-letter chunks ("trigrams") catch typos and middle-of-word matches, rarest chunk first;
   - only the best 600 candidates get the full `NameMatcher` score (prefix, word prefix,
     substring, initials, edit distance, letters-in-order).
4. **Paged lists.** Results and the before-you-type suggestions show 50 rows at a time; the next
   50 load when you scroll to the bottom.

Names are normalized once when indexed, not per comparison. The indexes are built in the
background after launch and updated in place when someone adds a place, climb, account or post.

Measured with a Python port of the same algorithm (the Swift version is several times faster):
110,000 items took 38 ms per query with the index versus 4.9 s scanning, and the top 10 results
matched a full scan for 18 of 20 test queries (the other 2 differed only in weak letters-in-order
matches near the bottom).

## Lookups instead of scans

`AppStore` keeps dictionaries that each mutation updates, so these are lookups, not scans:

| Question | Lookup |
| --- | --- |
| a post by id | `postAgeKeys` (position in `posts`) |
| sends at a place / by a climber / of a climb | `postIDsByPlace`, `postIDsByAuthor`, `postIDsByClimb` |
| "same climb" posts (grade averages) | `postIDsByClimbKey` |
| a crag's climbs | `climbIDsByPlace` |
| follower counts, followers, repost counts | `placeFollowerCounts`, `followerIDsByUser`, `repostCounts` |

Rankings (popular places, popular climbers, trending sends, most-filmed climbs) are sorted once
and cached until a follow, like or post changes them (`popularityVersion`, `engagementVersion`).

## Limits, and what to do past them

On-device indexes are comfortable into the hundreds of thousands of items. "Basically infinite"
(millions of sends, every climb in the world) means the phone can't hold everything, so with a
real backend:

- **Search on the server.** Postgres `pg_trgm` (same trigram idea, built into Supabase) is enough
  to start; Typesense or Meilisearch for typo tolerance and ranking at larger scale. The views
  already just ask for ids, so only the `AppStore.search…IDs` functions change.
- **Paginate feeds on the server.** The home feed still walks every loaded post (fine for the
  sample data); a server feed query with cursor pagination replaces it.
- **Spatial queries for the map.** The map currently walks places in popularity order and stops at
  250 markers. At scale, query by the visible region (PostGIS, or a geohash index) and cluster.
- **Counts and rankings from the server** (followers, trending), updated as events happen.
