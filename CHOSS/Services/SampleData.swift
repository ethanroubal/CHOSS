import Foundation

/// Seed data for the mock backend and SwiftUI previews.
/// Places are the real gym and crag directories (BundledPlaces); users, posts and climbs are samples.
enum SampleData {
    static let currentUserID: User.ID = "u_sam"

    /// Every gym and crag in the bundled US directories.
    static let places: [Place] = BundledPlaces.all

    // Real places from the bundled lists that the demo users and posts use.
    // (IDs come from the import scripts: name + coordinates.)
    static let brooklynGym = "p_gym_movement_gowanus_fadad8"                      // Movement Gowanus
    static let oaklandGym = "p_gym_great_western_power_company_touchstone_e47cf1" // Touchstone GWPC
    static let denverGym = "p_gym_the_spot_denver_49ae62"                         // The Spot Denver
    static let redRiverGorge = "p_crag_red_river_gorge_e58ba2"                    // Red River Gorge, KY
    static let bishop = "p_crag_bishop_area_652d05"                               // Bishop Area, CA (Buttermilks)
    static let yosemite = "p_crag_yosemite_national_park_33f84b"                  // Yosemite National Park, CA
    static let huecoTanks = "p_crag_hueco_tanks_89b091"                           // Hueco Tanks, TX
    static let willoughby = "p_crag_lake_willoughby_mount_pisgah_mount_hor_0197db" // Lake Willoughby, VT (ice)

    static let users: [User] = [
        User(id: "u_sam", username: "sam.sends", displayName: "Sam Rivera",
             bio: "Plastic puller, occasional crag rat. Projecting V7.", homePlaceIDs: [brooklynGym, bishop],
             boulderRange: GradeRange(system: .vScale, low: "V5", high: "V6"),
             ropeRange: GradeRange(system: .yds, low: "5.11b", high: "5.11d")),
        User(id: "u_alex", username: "alexcrimps", displayName: "Alex Chen",
             bio: "Crimps > slopers.", homePlaceIDs: [brooklynGym, denverGym],
             boulderRange: GradeRange(system: .vScale, low: "V7", high: "V8")),
        User(id: "u_jess", username: "jess_on_rock", displayName: "Jess Okafor",
             bio: "Sport climbing and road trips.", homePlaceIDs: [redRiverGorge],
             ropeRange: GradeRange(system: .yds, low: "5.12a", high: "5.12b")),
        User(id: "u_marco", username: "marco.boulders", displayName: "Marco Rossi",
             bio: "Winter bouldering in Hueco.", homePlaceIDs: [huecoTanks],
             boulderRange: GradeRange(system: .vScale, low: "V6", high: "V8"), showsGradeRange: false),
        User(id: "u_priya", username: "priyaclimbs", displayName: "Priya Nair",
             bio: "Highball enjoyer.", homePlaceIDs: [bishop, oaklandGym, yosemite],
             boulderRange: GradeRange(system: .vScale, low: "V6", high: nil)),
        User(id: "u_kenji", username: "kenji_k", displayName: "Kenji Watanabe",
             bio: "Trad dad. Cracks only.", homePlaceIDs: [yosemite]),
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

    /// Grades are now community averages of proposed grades, so a post's old "official" grade
    /// becomes the poster's proposal when they didn't make one.
    static let posts: [Post] = rawPosts.map { post in
        var post = post
        if post.proposedGrade == nil { post.proposedGrade = post.grade }
        post.grade = nil
        return post
    }

    private static let rawPosts: [Post] = [
        Post(id: "post_1", authorID: "u_alex", placeID: brooklynGym, videoURL: video(0),
             routeName: "Blue Crimp Traverse", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V6"), sendStyle: .flash,
             caption: "New blue problem went first try 😅 Heel hook at the lip is key.",
             createdAt: hoursAgo(2), likedBy: ["u_sam", "u_jess"],
             comments: [Comment(id: "c_1", authorID: "u_sam", text: "That heel is sick", createdAt: hoursAgo(1))]),
        Post(id: "post_2", authorID: "u_jess", placeID: redRiverGorge, climbID: "c_amarillo", videoURL: video(1),
             routeName: "Amarillo Sunset", discipline: .sport,
             grade: Grade(system: .yds, value: "5.11b"), proposedGrade: Grade(system: .yds, value: "5.11a"),
             sendStyle: .redpoint,
             caption: "Third session, finally clipped the chains. Beta: rest on the big jug before the roof.",
             createdAt: hoursAgo(5), likedBy: ["u_kenji"]),
        Post(id: "post_4", authorID: "u_priya", placeID: bishop, climbID: "c_iron_man", videoURL: video(3),
             routeName: "Iron Man Traverse", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V4"), sendStyle: .onsight,
             caption: "Warmup before the highballs.",
             createdAt: hoursAgo(20)),
        Post(id: "post_5", authorID: "u_kenji", placeID: yosemite, climbID: "c_midnight_lightning", videoURL: video(0),
             routeName: "Midnight Lightning", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V8"), sendStyle: .redpoint,
             caption: "Ten years of trying. Camp 4 legend finally goes.",
             createdAt: hoursAgo(30), likedBy: ["u_sam", "u_jess", "u_alex", "u_marco"]),
        Post(id: "post_6", authorID: "u_sam", placeID: brooklynGym, videoURL: video(1),
             routeName: "Pink Dyno", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V5"), proposedGrade: Grade(system: .vScale, value: "V6"),
             sendStyle: .redpoint,
             caption: "Stuck the dyno on attempt 23. Sandbagged, this is V6 all day.",
             createdAt: hoursAgo(40), likedBy: ["u_alex"]),
        Post(id: "post_7", authorID: "u_alex", placeID: denverGym, videoURL: video(2),
             routeName: "Board Problem #112", discipline: .boulder,
             grade: nil, proposedGrade: Grade(system: .vScale, value: "V7"), sendStyle: .redpoint,
             caption: "Visiting Denver. Ungraded board problem, felt about V7.",
             createdAt: hoursAgo(55)),
        Post(id: "post_8", authorID: "u_jess", placeID: nil, videoURL: video(3),
             routeName: "Hangboard session", discipline: .sport,
             grade: Grade(system: .yds, value: "5.11c"), sendStyle: .repeatSend,
             caption: "Not a send, just training. Posting for my followers only.",
             createdAt: hoursAgo(70)),
        Post(id: "post_9", authorID: "u_kenji", placeID: yosemite, climbID: "c_nutcracker", videoURL: video(1),
             routeName: "Nutcracker", discipline: .trad,
             grade: Grade(system: .yds, value: "5.8"), sendStyle: .onsight,
             caption: "Took the kids' godfather up his first Valley multipitch.",
             createdAt: hoursAgo(96), likedBy: ["u_priya"]),
        Post(id: "post_11", authorID: "u_priya", placeID: yosemite, climbID: "c_midnight_lightning",
             videoURL: video(2),
             routeName: "Midnight Lightning", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V8"), proposedGrade: Grade(system: .vScale, value: "V7"),
             sendStyle: .redpoint,
             caption: "Beta: left heel on the lightning bolt, then trust the slap to the lip. Feels V7 if you're tall.",
             createdAt: hoursAgo(150), likedBy: ["u_kenji", "u_sam"]),
        // More Yosemite sends, so the crag leaderboard has ties to show.
        Post(id: "post_13", authorID: "u_alex", placeID: yosemite, climbID: "c_midnight_lightning",
             videoURL: video(3), routeName: "Midnight Lightning", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V8"), sendStyle: .redpoint,
             caption: "Finally. The lightning bolt crux is all about the heel.",
             createdAt: hoursAgo(220), likedBy: ["u_sam"]),
        Post(id: "post_14", authorID: "u_marco", placeID: yosemite, climbID: "c_midnight_lightning",
             videoURL: video(1), routeName: "Midnight Lightning", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V8"), proposedGrade: Grade(system: .vScale, value: "V8"),
             sendStyle: .redpoint, caption: "Font training pays off in Camp 4.",
             createdAt: hoursAgo(260)),
        Post(id: "post_15", authorID: "u_sam", placeID: yosemite, climbID: "c_snake_dike",
             videoURL: video(2), routeName: "Snake Dike", discipline: .trad,
             grade: Grade(system: .yds, value: "5.7"), sendStyle: .onsight,
             caption: "Half Dome summit via the dike. Long day, huge views.",
             createdAt: hoursAgo(300), likedBy: ["u_kenji", "u_jess"]),
        Post(id: "post_16", authorID: "u_sam", placeID: yosemite, climbID: "c_nutcracker",
             videoURL: video(0), routeName: "Nutcracker", discipline: .trad,
             grade: Grade(system: .yds, value: "5.8"), sendStyle: .onsight,
             caption: "Mantel crux on the last pitch is spicy.",
             createdAt: hoursAgo(310)),
        Post(id: "post_17", authorID: "u_sam", placeID: yosemite, videoURL: video(3),
             routeName: "Blues Brothers", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V4"), sendStyle: .flash,
             caption: "Camp 4 warmup circuit.",
             createdAt: hoursAgo(320)),
        Post(id: "post_18", authorID: "u_jess", placeID: yosemite, climbID: "c_separate_reality",
             videoURL: video(1), routeName: "Separate Reality", discipline: .trad,
             grade: Grade(system: .yds, value: "5.11d"), sendStyle: .redpoint,
             caption: "Hanging out over the valley on the roof crack. Bucket list ✅",
             createdAt: hoursAgo(340), likedBy: ["u_kenji", "u_sam", "u_priya"]),
        Post(id: "post_19", authorID: "u_jess", placeID: willoughby, climbID: "c_called_on_account_of_rains",
             videoURL: video(2), routeName: "Called on Account of Rains", discipline: .ice,
             proposedGrade: Grade(system: .waterIce, value: "WI4+"), sendStyle: .redpoint,
             caption: "Fat blue ice on Pisgah this week. Screws went in like butter.",
             createdAt: hoursAgo(90), likedBy: ["u_sam", "u_kenji"]),
        Post(id: "post_10", authorID: "u_priya", placeID: oaklandGym, videoURL: video(0),
             routeName: "Yellow Comp Slab", discipline: .boulder,
             grade: Grade(system: .vScale, value: "V5"), sendStyle: .flash,
             caption: "Slab day. Trust your feet.",
             createdAt: hoursAgo(120)),
    ]

    static let climbs: [Climb] = [
        // Yosemite
        Climb(id: "c_midnight_lightning", placeID: yosemite, name: "Midnight Lightning", area: "Camp 4",
              discipline: .boulder, grade: Grade(system: .vScale, value: "V8"),
              about: "The Columbia Boulder's famous line, marked by the chalk lightning bolt."),
        Climb(id: "c_nutcracker", placeID: yosemite, name: "Nutcracker", area: "Manure Pile Buttress",
              discipline: .trad, grade: Grade(system: .yds, value: "5.8"),
              about: "Five-pitch Valley classic, one of the first routes climbed clean with nuts."),
        Climb(id: "c_snake_dike", placeID: yosemite, name: "Snake Dike", area: "Half Dome",
              discipline: .trad, grade: Grade(system: .yds, value: "5.7")),
        Climb(id: "c_separate_reality", placeID: yosemite, name: "Separate Reality", area: "Middle Cathedral area",
              discipline: .trad, grade: Grade(system: .yds, value: "5.11d")),
        // Lake Willoughby (ice)
        Climb(id: "c_called_on_account_of_rains", placeID: willoughby, name: "Called on Account of Rains",
              area: "Mount Pisgah", discipline: .ice, grade: Grade(system: .waterIce, value: "WI4")),
        // Bishop Area (Buttermilks)
        Climb(id: "c_iron_man", placeID: bishop, name: "Iron Man Traverse", area: "Buttermilks · Grandpa Peabody",
              discipline: .boulder, grade: Grade(system: .vScale, value: "V4")),
        Climb(id: "c_mandala", placeID: bishop, name: "The Mandala", area: "Buttermilks · Mandala Boulder",
              discipline: .boulder, grade: Grade(system: .vScale, value: "V12")),
        // Red River Gorge
        Climb(id: "c_amarillo", placeID: redRiverGorge, name: "Amarillo Sunset", area: "Drive-By Crag",
              discipline: .sport, grade: Grade(system: .yds, value: "5.11b")),
        Climb(id: "c_southern_smoke", placeID: redRiverGorge, name: "Southern Smoke", area: "Motherlode",
              discipline: .sport, grade: Grade(system: .yds, value: "5.14c")),
    ]

    static let snapshot = AppSnapshot(
        users: users,
        places: places,
        climbs: climbs,
        posts: posts,
        followedPlaces: [
            "u_sam": [brooklynGym, bishop, huecoTanks],
            "u_alex": [brooklynGym, denverGym],
            "u_jess": [redRiverGorge, brooklynGym],
            "u_marco": [huecoTanks],
            "u_priya": [bishop, oaklandGym, yosemite],
            "u_kenji": [yosemite, redRiverGorge],
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
            Repost(id: "r_2", userID: "u_alex", postID: "post_4", createdAt: hoursAgo(6)),
        ]
    )
}
