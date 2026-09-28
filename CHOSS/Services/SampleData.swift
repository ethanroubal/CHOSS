import Foundation

/// Seed data for the mock backend and SwiftUI previews.
/// Gyms are fictional; crags are real, well-known areas.
enum SampleData {
    static let currentUserID: User.ID = "u_sam"

    static let places: [Place] = [
        Place(id: "p_granite_works", name: "Granite Works Climbing", kind: .gym,
              city: "Brooklyn", region: "NY", country: "USA",
              latitude: 40.6782, longitude: -73.9942,
              disciplines: [.boulder, .sport, .topRope],
              about: "Bouldering and roped climbing with a fresh set every Tuesday."),
        Place(id: "p_crux_collective", name: "Crux Collective", kind: .gym,
              city: "Oakland", region: "CA", country: "USA",
              latitude: 37.8044, longitude: -122.2712,
              disciplines: [.boulder],
              about: "Bouldering-only gym. Comp-style resets every other week."),
        Place(id: "p_high_point", name: "High Point Bouldering", kind: .gym,
              city: "Denver", region: "CO", country: "USA",
              latitude: 39.7392, longitude: -104.9903,
              disciplines: [.boulder, .sport],
              about: "Steep walls, a 45° board, and a 50 ft lead wall."),
        Place(id: "p_rrg", name: "Red River Gorge", kind: .crag,
              city: "Slade", region: "KY", country: "USA",
              latitude: 37.8331, longitude: -83.6827,
              disciplines: [.sport, .trad],
              about: "Overhanging sandstone sport climbing and endless jugs."),
        Place(id: "p_buttermilks", name: "Buttermilk Boulders", kind: .crag,
              city: "Bishop", region: "CA", country: "USA",
              latitude: 37.3272, longitude: -118.5770,
              disciplines: [.boulder],
              about: "Giant granite highballs below the Sierra."),
        Place(id: "p_yosemite", name: "Yosemite Valley", kind: .crag,
              city: "Yosemite", region: "CA", country: "USA",
              latitude: 37.7456, longitude: -119.5936,
              disciplines: [.trad, .boulder, .sport],
              about: "Big walls, splitter cracks and the Camp 4 boulders."),
        Place(id: "p_font", name: "Fontainebleau", kind: .crag,
              city: "Fontainebleau", region: "Île-de-France", country: "France",
              latitude: 48.4047, longitude: 2.7016,
              disciplines: [.boulder],
              about: "The birthplace of modern bouldering. Sandstone in the forest."),
    ]

    static let users: [User] = [
        User(id: "u_sam", username: "sam.sends", displayName: "Sam Rivera",
             bio: "Plastic puller, occasional crag rat. Projecting V7.", homePlaceID: "p_granite_works",
             boulderRange: GradeRange(system: .vScale, low: "V5", high: "V6"),
             ropeRange: GradeRange(system: .yds, low: "5.11b", high: "5.11d")),
        User(id: "u_alex", username: "alexcrimps", displayName: "Alex Chen",
             bio: "Crimps > slopers. Route setter.", homePlaceID: "p_granite_works",
             boulderRange: GradeRange(system: .vScale, low: "V7", high: "V8")),
        User(id: "u_jess", username: "jess_on_rock", displayName: "Jess Okafor",
             bio: "Sport climbing and road trips.", homePlaceID: "p_rrg",
             ropeRange: GradeRange(system: .yds, low: "5.12a", high: "5.12b")),
        User(id: "u_marco", username: "marco.boulders", displayName: "Marco Rossi",
             bio: "Font every winter.", homePlaceID: "p_font",
             boulderRange: GradeRange(system: .font, low: "7A", high: "7B"), showsGradeRange: false),
        User(id: "u_priya", username: "priyaclimbs", displayName: "Priya Nair",
             bio: "Highball enjoyer.", homePlaceID: "p_buttermilks",
             boulderRange: GradeRange(system: .vScale, low: "V6", high: nil)),
        User(id: "u_kenji", username: "kenji_k", displayName: "Kenji Watanabe",
             bio: "Trad dad. Cracks only.", homePlaceID: "p_yosemite"),
    ]

    // Placeholder clips until real uploads exist.
    private static let sampleVideos: [URL] = [
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
    ].compactMap(URL.init(string:))

    private static func video(_ index: Int) -> URL? {
        sampleVideos[index % sampleVideos.count]
    }

    private static func hoursAgo(_ hours: Double) -> Date {
        Date().addingTimeInterval(-hours * 3600)
    }

    static let posts: [Post] = [
        Post(id: "post_1", authorID: "u_alex", placeID: "p_granite_works", videoURL: video(0),
             routeName: "Blue Crimp Traverse", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V6"), sendStyle: .flash,
             caption: "Set this one yesterday and it went first try 😅 Heel hook at the lip is key.",
             createdAt: hoursAgo(2), likedBy: ["u_sam", "u_jess"],
             comments: [Comment(id: "c_1", authorID: "u_sam", text: "That heel is sick", createdAt: hoursAgo(1))]),
        Post(id: "post_2", authorID: "u_jess", placeID: "p_rrg", climbID: "c_amarillo", videoURL: video(1),
             routeName: "Amarillo Sunset", discipline: .sport,
             grade: Grade(system: .yds, value: "5.11b"), proposedGrade: Grade(system: .yds, value: "5.11a"),
             sendStyle: .redpoint,
             caption: "Third session, finally clipped the chains. Beta: rest on the big jug before the roof.",
             createdAt: hoursAgo(5), likedBy: ["u_kenji"]),
        Post(id: "post_3", authorID: "u_marco", placeID: "p_font", climbID: "c_marie_rose", videoURL: video(2),
             routeName: "La Marie-Rose", discipline: .boulder,
             grade: Grade(system: .font, value: "6A"), sendStyle: .repeatSend,
             caption: "Lap on the classic. Perfect friction this morning.",
             createdAt: hoursAgo(9), likedBy: ["u_priya", "u_sam", "u_alex"]),
        Post(id: "post_4", authorID: "u_priya", placeID: "p_buttermilks", climbID: "c_iron_man", videoURL: video(3),
             routeName: "Iron Man Traverse", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V4"), sendStyle: .onsight,
             caption: "Warmup before the highballs.",
             createdAt: hoursAgo(20)),
        Post(id: "post_5", authorID: "u_kenji", placeID: "p_yosemite", climbID: "c_midnight_lightning", videoURL: video(0),
             routeName: "Midnight Lightning", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V8"), sendStyle: .redpoint,
             caption: "Ten years of trying. Camp 4 legend finally goes.",
             createdAt: hoursAgo(30), likedBy: ["u_sam", "u_jess", "u_alex", "u_marco"]),
        Post(id: "post_6", authorID: "u_sam", placeID: "p_granite_works", videoURL: video(1),
             routeName: "Pink Dyno", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V5"), proposedGrade: Grade(system: .vScale, value: "V6"),
             sendStyle: .redpoint,
             caption: "Stuck the dyno on attempt 23. Sandbagged, this is V6 all day.",
             createdAt: hoursAgo(40), likedBy: ["u_alex"]),
        Post(id: "post_7", authorID: "u_alex", placeID: "p_high_point", videoURL: video(2),
             routeName: "Board Problem #112", discipline: .boulder,
             grade: nil, proposedGrade: Grade(system: .vScale, value: "V7"), sendStyle: .redpoint,
             caption: "Visiting Denver. Ungraded board problem, felt about V7.",
             createdAt: hoursAgo(55)),
        Post(id: "post_8", authorID: "u_jess", placeID: nil, videoURL: video(3),
             routeName: "Hangboard session", discipline: .sport,
             grade: Grade(system: .yds, value: "5.11c"), sendStyle: .repeatSend,
             caption: "Not a send, just training. Posting for my followers only.",
             createdAt: hoursAgo(70)),
        Post(id: "post_9", authorID: "u_kenji", placeID: "p_yosemite", climbID: "c_nutcracker", videoURL: video(1),
             routeName: "Nutcracker", discipline: .trad,
             grade: Grade(system: .yds, value: "5.8"), sendStyle: .onsight,
             caption: "Took the kids' godfather up his first Valley multipitch.",
             createdAt: hoursAgo(96), likedBy: ["u_priya"]),
        Post(id: "post_11", authorID: "u_priya", placeID: "p_yosemite", climbID: "c_midnight_lightning",
             videoURL: video(2),
             routeName: "Midnight Lightning", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V8"), proposedGrade: Grade(system: .vScale, value: "V7"),
             sendStyle: .redpoint,
             caption: "Beta: left heel on the lightning bolt, then trust the slap to the lip. Feels V7 if you're tall.",
             createdAt: hoursAgo(150), likedBy: ["u_kenji", "u_sam"]),
        Post(id: "post_12", authorID: "u_marco", placeID: "p_font", climbID: "c_marie_rose", videoURL: video(3),
             routeName: "La Marie-Rose", discipline: .boulder,
             grade: Grade(system: .font, value: "6A"), sendStyle: .flash,
             caption: "Flashed it on my first Font trip years ago, filmed the lap for a friend. Feet high on the right!",
             createdAt: hoursAgo(200)),
        Post(id: "post_10", authorID: "u_priya", placeID: "p_crux_collective", videoURL: video(0),
             routeName: "Yellow Comp Slab", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V5"), sendStyle: .flash,
             caption: "Slab day at Crux. Trust your feet.",
             createdAt: hoursAgo(120)),
    ]

    static let climbs: [Climb] = [
        // Yosemite
        Climb(id: "c_midnight_lightning", placeID: "p_yosemite", name: "Midnight Lightning", area: "Camp 4",
              discipline: .boulder, grade: Grade(system: .vScale, value: "V8"),
              about: "The Columbia Boulder's famous line, marked by the chalk lightning bolt."),
        Climb(id: "c_nutcracker", placeID: "p_yosemite", name: "Nutcracker", area: "Manure Pile Buttress",
              discipline: .trad, grade: Grade(system: .yds, value: "5.8"),
              about: "Five-pitch Valley classic, one of the first routes climbed clean with nuts."),
        Climb(id: "c_snake_dike", placeID: "p_yosemite", name: "Snake Dike", area: "Half Dome",
              discipline: .trad, grade: Grade(system: .yds, value: "5.7")),
        Climb(id: "c_separate_reality", placeID: "p_yosemite", name: "Separate Reality", area: "Middle Cathedral area",
              discipline: .trad, grade: Grade(system: .yds, value: "5.11d")),
        // Buttermilks
        Climb(id: "c_iron_man", placeID: "p_buttermilks", name: "Iron Man Traverse", area: "Grandpa Peabody",
              discipline: .boulder, grade: Grade(system: .vScale, value: "V4")),
        Climb(id: "c_mandala", placeID: "p_buttermilks", name: "The Mandala", area: "Mandala Boulder",
              discipline: .boulder, grade: Grade(system: .vScale, value: "V12")),
        // Fontainebleau
        Climb(id: "c_marie_rose", placeID: "p_font", name: "La Marie-Rose", area: "Bas Cuvier",
              discipline: .boulder, grade: Grade(system: .font, value: "6A"),
              about: "First 6A in Fontainebleau (1946). Polished, famous, mandatory."),
        Climb(id: "c_rainbow_rocket", placeID: "p_font", name: "Rainbow Rocket", area: "Bas Cuvier",
              discipline: .boulder, grade: Grade(system: .font, value: "8A")),
        // Red River Gorge
        Climb(id: "c_amarillo", placeID: "p_rrg", name: "Amarillo Sunset", area: "Drive-By Crag",
              discipline: .sport, grade: Grade(system: .yds, value: "5.11b")),
        Climb(id: "c_southern_smoke", placeID: "p_rrg", name: "Southern Smoke", area: "Motherlode",
              discipline: .sport, grade: Grade(system: .yds, value: "5.14c")),
    ]

    static let snapshot = AppSnapshot(
        users: users,
        places: places,
        climbs: climbs,
        posts: posts,
        followedPlaces: [
            "u_sam": ["p_granite_works", "p_buttermilks", "p_font"],
            "u_alex": ["p_granite_works", "p_high_point"],
            "u_jess": ["p_rrg", "p_granite_works"],
            "u_marco": ["p_font"],
            "u_priya": ["p_buttermilks", "p_crux_collective", "p_yosemite"],
            "u_kenji": ["p_yosemite", "p_rrg"],
        ],
        followedUsers: [
            "u_sam": ["u_alex", "u_jess"],
            "u_alex": ["u_sam"],
            "u_jess": ["u_kenji", "u_sam"],
            "u_marco": ["u_priya"],
            "u_priya": ["u_marco", "u_kenji", "u_sam"],
            "u_kenji": ["u_jess"],
        ],
        reposts: [
            Repost(id: "r_1", userID: "u_jess", postID: "post_5", createdAt: hoursAgo(3)),
            Repost(id: "r_2", userID: "u_alex", postID: "post_3", createdAt: hoursAgo(6)),
        ],
        conversations: [
            Conversation(id: "dm_sam_alex", participantIDs: ["u_sam", "u_alex"]),
        ],
        messages: [
            Message(id: "m_1", conversationID: "dm_sam_alex", senderID: "u_alex",
                    text: "You have to try this one", sharedPostID: "post_5", createdAt: hoursAgo(12)),
            Message(id: "m_2", conversationID: "dm_sam_alex", senderID: "u_sam",
                    text: "Legendary. Road trip?", sharedPostID: nil, createdAt: hoursAgo(11)),
        ]
    )
}
