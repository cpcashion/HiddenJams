//
//  GenreMatcher.swift
//  HiddenJams
//
//  Decides whether an artist's Spotify genres belong to the genres the user
//  picked. Matching is whole-word on canonical labels, so "liquid funk" never
//  passes as Funk, "witch house" never passes as House, "synthpop" never
//  passes as plain Pop, and "indie rock" never passes as Drum and Bass.
//
//  Every genre in the picker has a curated family: which labels count, which
//  look similar but don't, and which Spotify genres to search. Genres that
//  come from the user's own profile ("uk drum and bass", "bedroom pop") match
//  on their exact phrase, and fall back to their parent family only when the
//  exact genre runs dry.
//

import Foundation

/// Pure logic with no shared state, so it isn't tied to the main actor.
nonisolated struct GenreMatcher {

    struct Family {
        /// Canonical key, e.g. "dnb" for "Drum and Bass".
        let key: String
        /// Labels containing any of these phrases belong to the family...
        let accepts: [[String]]
        /// ...unless they also contain one of these.
        let rejects: [[String]]
        /// Parent-family phrases, accepted only as a fallback (tier 1).
        let broader: [[String]]
        let broaderRejects: [[String]]
        /// Spotify genre names to search for this family.
        let searches: [String]
        /// Parent-family searches, used only when the exact genre runs dry.
        let broaderSearches: [String]
        /// K-Pop, Anime and region-specific genres may have titles in
        /// non-Latin scripts; every other family keeps the script filter.
        let allowsNonLatinScript: Bool
        /// Profile genres also accept multi-word labels they contain
        /// ("uk alternative hip hop" accepts "alternative hip hop").
        let acceptsContainedLabels: Bool
        /// Tokens of the user's selection itself.
        let selectionTokens: [String]
    }

    /// One entry per distinct selected genre ("Hip Hop" + "Rap" = one family).
    let families: [Family]
    private let exclusions: [ExclusionGroup]

    init(selections: [String], userExcluded: [String] = []) {
        var seen = Set<String>()
        var resolved: [Family] = []
        for selection in selections {
            let family = Self.family(for: selection)
            guard !family.key.isEmpty, seen.insert(family.key).inserted else { continue }
            resolved.append(family)
        }
        families = resolved

        // An exclusion group is lifted when the selection itself is in that
        // world (picking Christian lifts the religious filter, Latin lifts
        // the Latin filter, and so on).
        var active: [ExclusionGroup] = []
        for group in Self.systemExclusions {
            let lifted = resolved.contains { family in
                group.phrases.contains { phrase in
                    Self.contains(family.selectionTokens, phrase)
                        || family.accepts.contains { Self.contains($0, phrase) }
                }
            }
            if !lifted { active.append(group) }
        }
        for raw in userExcluded {
            let phrase = Self.tokens(raw)
            guard !phrase.isEmpty else { continue }
            let selected = resolved.contains { Self.contains($0.selectionTokens, phrase) }
            if !selected { active.append(ExclusionGroup(phrases: [phrase], except: [])) }
        }
        exclusions = active
    }

    // MARK: - Matching

    /// Best match for an artist's genre labels: tier 0 = the selected genre
    /// itself, tier 1 = only its parent family. The preferred family (the one
    /// whose search found the track) wins ties. Nil when nothing matches.
    func match(_ genres: [String], preferring preferred: Int? = nil) -> (family: Int, tier: Int)? {
        let labels = genres.map(Self.tokens).filter { !$0.isEmpty }
        guard !labels.isEmpty, !families.isEmpty else { return nil }
        var order = Array(families.indices)
        if let preferred, families.indices.contains(preferred) {
            order.removeAll { $0 == preferred }
            order.insert(preferred, at: 0)
        }
        var fallback: (family: Int, tier: Int)?
        for index in order {
            guard let tier = Self.tier(labels, families[index]) else { continue }
            if tier == 0 { return (index, 0) }
            if fallback == nil { fallback = (index, tier) }
        }
        return fallback
    }

    /// True when any label falls in a genre the user didn't pick and the app
    /// keeps out by default (holiday, kids, soundtracks, anime, religious,
    /// Latin), or one the user excluded in settings.
    func isExcluded(_ genres: [String]) -> Bool {
        let labels = genres.map(Self.tokens)
        return labels.contains { label in
            exclusions.contains { group in
                group.phrases.contains { Self.contains(label, $0) }
                    && !group.except.contains { Self.contains(label, $0) }
            }
        }
    }

    private static func tier(_ labels: [[String]], _ family: Family) -> Int? {
        var best: Int?
        for label in labels {
            let accepted = family.accepts.contains { contains(label, $0) }
                && !family.rejects.contains { contains(label, $0) }
            if accepted { return 0 }
            if family.acceptsContainedLabels, label.count >= 2,
               family.accepts.contains(where: { contains($0, label) }) {
                return 0
            }
            if best == nil,
               family.broader.contains(where: { contains(label, $0) }),
               !family.broaderRejects.contains(where: { contains(label, $0) }) {
                best = 1
            }
        }
        return best
    }

    // MARK: - Canonical labels

    /// Canonical word list for a genre label: lowercased, accents folded,
    /// punctuation dropped, and spelling variants collapsed so they compare
    /// equal ("Drum & Bass", "drum-and-bass", "DnB" -> ["dnb"];
    /// "Hip-Hop" -> ["hiphop"]; "R&B" -> ["rnb"]; "K-Pop" -> ["kpop"]).
    static func tokens(_ raw: String) -> [String] {
        var text = raw.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        text = text.replacingOccurrences(of: "&", with: " and ")
        text = text.replacingOccurrences(of: "'", with: "")
        text = text.replacingOccurrences(of: "\u{2019}", with: "")
        let cleaned = String(text.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        })
        // A lone "n" means "and": drum n bass, rock n roll, r n b.
        var words: [String] = cleaned.split(separator: " ").map { $0 == "n" ? "and" : String($0) }

        var collapsed: [String] = []
        var i = 0
        while i < words.count {
            var matched = false
            for rule in phraseRules {
                let end = i + rule.pattern.count
                if end <= words.count, Array(words[i..<end]) == rule.pattern {
                    collapsed.append(rule.replacement)
                    i = end
                    matched = true
                    break
                }
            }
            if !matched {
                collapsed.append(words[i])
                i += 1
            }
        }
        words = collapsed

        // Single-letter prefixes join the next word: k pop -> kpop,
        // j rock -> jrock, p funk -> pfunk, g funk -> gfunk, 2 step -> 2step.
        var joined: [String] = []
        i = 0
        while i < words.count {
            if words[i].count == 1, i + 1 < words.count {
                joined.append(words[i] + words[i + 1])
                i += 2
            } else {
                joined.append(words[i])
                i += 1
            }
        }
        return joined
    }

    /// True when `phrase` appears in `label` as whole consecutive words.
    static func contains(_ label: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= label.count else { return false }
        for start in 0...(label.count - phrase.count)
        where Array(label[start..<(start + phrase.count)]) == phrase {
            return true
        }
        return false
    }

    /// Does `label` contain `phrase` as whole words, after canonicalization?
    static func label(_ label: String, contains phrase: String) -> Bool {
        contains(tokens(label), tokens(phrase))
    }

    private static let phraseRules: [(pattern: [String], replacement: String)] = [
        (["rhythm", "and", "blues"], "rnb"),
        (["drum", "and", "bass"], "dnb"),
        (["drum", "bass"], "dnb"),
        (["drumandbass"], "dnb"),
        (["drumnbass"], "dnb"),
        (["d", "and", "b"], "dnb"),
        (["r", "and", "b"], "rnb"),
        (["hip", "hop"], "hiphop"),
        (["synth", "pop"], "synthpop"),
        (["electro", "pop"], "electropop"),
        (["hyper", "pop"], "hyperpop"),
        (["lo", "fi"], "lofi"),
        (["dub", "step"], "dubstep"),
    ]

    // MARK: - Families

    static func family(for selection: String) -> Family {
        let selectionTokens = tokens(selection)
        let key = selectionTokens.joined(separator: " ")
        if let spec = curated[key] {
            return Family(
                key: spec.key,
                accepts: spec.accepts.map(tokens),
                rejects: spec.rejects.map(tokens),
                broader: [],
                broaderRejects: [],
                searches: spec.searches,
                broaderSearches: [],
                allowsNonLatinScript: spec.nonLatin,
                acceptsContainedLabels: false,
                selectionTokens: selectionTokens
            )
        }
        // A genre from the user's own profile: match its exact phrase, and
        // fall back to the most specific picker family it belongs to
        // ("uk drum and bass" -> Drum and Bass, not all of Electronic).
        let parent = specs
            .filter { spec in
                spec.accepts.map(tokens).contains { contains(selectionTokens, $0) }
                    && !spec.rejects.map(tokens).contains { contains(selectionTokens, $0) }
            }
            .min { $0.accepts.count < $1.accepts.count }
        let trimmed = selection.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return Family(
            key: key,
            accepts: selectionTokens.isEmpty ? [] : [selectionTokens],
            rejects: [],
            broader: parent?.accepts.map(tokens) ?? [],
            broaderRejects: parent?.rejects.map(tokens) ?? [],
            searches: trimmed.isEmpty ? [] : [trimmed],
            broaderSearches: parent?.searches ?? [],
            allowsNonLatinScript: selectionTokens.contains { regionalWords.contains($0) },
            acceptsContainedLabels: true,
            selectionTokens: selectionTokens
        )
    }

    /// Words marking a genre whose music is usually titled in a non-Latin
    /// script ("russian dnb", "japanese indie", "mandopop").
    private static let regionalWords: Set<String> = [
        "japanese", "japan", "jpop", "jrock", "jrap", "anime", "vocaloid", "kayokyoku", "enka",
        "korean", "kpop", "krap", "kindie", "chinese", "mandopop", "cantopop", "cpop",
        "taiwanese", "russian", "ukrainian", "belarusian", "bulgarian", "serbian", "macedonian",
        "kazakh", "thai", "arabic", "egyptian", "lebanese", "persian", "iranian", "hebrew",
        "israeli", "greek", "hindi", "bollywood", "tamil", "telugu", "punjabi", "bengali",
        "nepali", "georgian", "armenian", "mongolian",
    ]

    private struct Spec {
        let names: [String]
        let accepts: [String]
        let rejects: [String]
        let searches: [String]
        var nonLatin = false

        var key: String { GenreMatcher.tokens(names[0]).joined(separator: " ") }
    }

    private static let curated: [String: Spec] = {
        var map: [String: Spec] = [:]
        for spec in specs {
            for name in spec.names {
                map[tokens(name).joined(separator: " ")] = spec
            }
        }
        return map
    }()

    /// The genre picker's genres. `searches` are Spotify genre names, and
    /// every search genre is itself accepted by its family.
    private static let specs: [Spec] = [
        Spec(
            names: ["Drum and Bass", "dnb"],
            accepts: ["drum and bass", "liquid funk", "neurofunk", "jump up", "darkstep",
                      "techstep", "drumfunk", "deep liquid", "halftime", "crossbreed", "jungle"],
            rejects: ["jungle terror"],
            searches: ["drum and bass", "liquid funk", "neurofunk", "jump up", "uk dnb",
                       "dancefloor dnb", "deep liquid", "halftime dnb", "darkstep", "techstep",
                       "atmospheric dnb", "minimal dnb", "dutch dnb", "belgian dnb", "jungle"]
        ),
        Spec(
            names: ["Jungle"],
            accepts: ["jungle"],
            rejects: ["jungle terror"],
            searches: ["jungle", "ragga jungle"]
        ),
        Spec(
            names: ["House"],
            accepts: ["house", "microhouse"],
            rejects: ["witch house"],
            searches: ["house", "deep house", "tech house", "lo-fi house", "microhouse",
                       "chicago house", "acid house", "afro house", "outsider house",
                       "french house", "progressive house", "tribal house", "bass house",
                       "disco house", "funky house"]
        ),
        Spec(
            names: ["Techno"],
            accepts: ["techno"],
            rejects: ["techno pop"],
            searches: ["techno", "minimal techno", "dub techno", "acid techno", "hard techno",
                       "detroit techno", "industrial techno", "melodic techno", "german techno",
                       "dark techno", "deep techno", "ambient techno", "raw techno"]
        ),
        Spec(
            names: ["Ambient"],
            accepts: ["ambient", "drone", "space music"],
            rejects: ["drone metal"],
            searches: ["ambient", "dark ambient", "drone", "ambient idm", "space ambient",
                       "ambient techno", "ambient dub", "experimental ambient", "deep ambient"]
        ),
        Spec(
            names: ["Electronic", "electronica"],
            accepts: ["electronic", "electronica", "edm", "idm", "techno", "house", "trance",
                      "ambient", "downtempo", "dubstep", "drum and bass", "jungle", "breakbeat",
                      "breaks", "electro", "synthwave", "chillwave", "vaporwave", "glitch",
                      "trip hop", "uk garage", "speed garage", "future garage", "bass music",
                      "future bass", "electroclash", "big beat", "footwork", "juke", "hardstyle",
                      "gabber", "happy hardcore", "uk hardcore", "psytrance", "leftfield",
                      "microhouse", "electropop", "synthpop", "chiptune", "lo-fi beats",
                      "nu disco", "ebm", "uk funky", "breakcore", "complextro", "brostep",
                      "bassline", "drone", "darksynth", "retrowave", "outrun", "folktronica",
                      "indietronica", "livetronica", "liquid funk", "neurofunk"],
            rejects: ["ambient folk", "drone metal", "drone folk", "jungle terror"],
            searches: ["electronic", "electronica", "idm", "downtempo", "leftfield",
                       "experimental electronic", "deep house", "techno", "ambient", "uk garage",
                       "bass music", "electro", "breakbeat", "glitch", "microhouse",
                       "minimal techno", "future garage", "chillwave", "synthwave", "trip hop",
                       "edm", "dubstep", "drum and bass"]
        ),
        Spec(
            names: ["Dance", "edm"],
            accepts: ["dance", "edm", "house", "techno", "trance", "eurodance", "disco", "big room",
                      "hardstyle", "uk garage", "electro house", "slap house", "melbourne bounce",
                      "jersey club", "baltimore club", "uk funky", "eurobeat", "hi nrg"],
            rejects: ["witch house"],
            searches: ["dance", "edm", "house", "dance pop", "nu disco", "deep house", "tech house",
                       "uk dance", "eurodance", "electro house", "progressive house",
                       "indie dance", "disco house", "trance"]
        ),
        Spec(
            names: ["Hip Hop", "rap"],
            accepts: ["hip hop", "rap", "trap", "drill", "boom bap", "grime", "phonk", "g funk",
                      "crunk", "hyphy", "horrorcore"],
            rejects: ["rap rock", "rap metal", "drill and bass", "edm trap", "trap edm"],
            searches: ["hip hop", "underground hip hop", "rap", "trap", "boom bap",
                       "alternative hip hop", "drill", "experimental hip hop", "conscious hip hop",
                       "southern hip hop", "east coast hip hop", "west coast rap",
                       "abstract hip hop", "uk hip hop", "underground rap", "jazz rap"]
        ),
        Spec(
            names: ["R&B"],
            accepts: ["r&b", "neo soul", "new jack swing", "quiet storm", "urban contemporary",
                      "trap soul"],
            rejects: [],
            searches: ["r&b", "alternative r&b", "contemporary r&b", "indie r&b", "neo soul",
                       "uk contemporary r&b", "chill r&b"]
        ),
        Spec(
            names: ["Soul"],
            accepts: ["soul", "motown"],
            rejects: ["trap soul"],
            searches: ["soul", "neo soul", "retro soul", "southern soul", "northern soul",
                       "classic soul", "psychedelic soul", "indie soul", "uk neo soul"]
        ),
        Spec(
            names: ["Funk"],
            accepts: ["funk", "p funk"],
            rejects: ["liquid funk", "carioca", "paulista", "ostentacao", "mtg", "rj", "bh",
                      "consciente", "mandelao", "proibidao", "brazilian", "brega", "150 bpm",
                      "funk melody", "das antigas"],
            searches: ["funk", "p funk", "jazz funk", "funk rock", "deep funk", "nu funk"]
        ),
        Spec(
            names: ["Reggae"],
            accepts: ["reggae", "dub", "dancehall", "rocksteady", "lovers rock", "ragga"],
            rejects: ["dub techno", "ragga jungle", "dub house"],
            searches: ["reggae", "roots reggae", "modern reggae", "dub", "dancehall",
                       "lovers rock", "reggae fusion", "uk reggae", "rocksteady"]
        ),
        Spec(
            names: ["Reggaeton"],
            accepts: ["reggaeton", "dembow", "perreo", "urbano latino"],
            rejects: [],
            searches: ["reggaeton", "reggaeton flow", "urbano latino", "dembow"]
        ),
        Spec(
            names: ["Latin"],
            accepts: ["latin", "latino", "reggaeton", "salsa", "bachata", "cumbia", "merengue",
                      "tango", "bossa nova", "samba", "mpb", "mariachi", "ranchera", "norteno",
                      "banda", "corrido", "corridos", "vallenato", "bolero", "tropical",
                      "musica mexicana", "urbano latino", "dembow", "sertanejo", "pagode",
                      "forro", "flamenco", "espanol"],
            rejects: ["tropical house"],
            searches: ["latin", "latin pop", "latin alternative", "latin indie", "cumbia", "salsa",
                       "bachata", "latin rock", "reggaeton", "musica mexicana", "bossa nova",
                       "tropical"]
        ),
        Spec(
            names: ["K-Pop"],
            accepts: ["k-pop", "korean", "k-rap", "k-indie", "k-rock", "k-ballad", "k-hip hop",
                      "k-r&b"],
            rejects: [],
            searches: ["k-pop", "k-pop girl group", "k-pop boy group", "korean pop", "k-indie",
                       "korean r&b", "k-rap"],
            nonLatin: true
        ),
        Spec(
            names: ["Anime"],
            accepts: ["anime", "otacore", "vocaloid"],
            rejects: [],
            searches: ["anime", "anime rock", "anime score", "otacore", "vocaloid", "anime lo-fi"],
            nonLatin: true
        ),
        Spec(
            names: ["Gospel"],
            accepts: ["gospel"],
            rejects: [],
            searches: ["gospel", "gospel r&b", "contemporary gospel", "traditional gospel",
                       "southern gospel"]
        ),
        Spec(
            names: ["Christian", "ccm"],
            accepts: ["christian", "ccm", "worship", "gospel", "praise"],
            rejects: [],
            searches: ["christian", "christian alternative rock", "christian indie",
                       "christian hip hop", "christian pop", "ccm", "christian rock",
                       "christian music"]
        ),
        Spec(
            names: ["Worship"],
            accepts: ["worship", "praise", "ccm"],
            rejects: [],
            searches: ["worship", "ccm"]
        ),
        Spec(
            names: ["Country"],
            accepts: ["country", "americana", "bluegrass", "honky tonk", "red dirt"],
            rejects: [],
            searches: ["country", "alt country", "outlaw country", "texas country", "red dirt",
                       "contemporary country", "country rock", "americana", "bluegrass",
                       "traditional country", "modern country rock"]
        ),
        Spec(
            names: ["Folk"],
            accepts: ["folk", "americana", "bluegrass", "singer-songwriter", "neofolk",
                      "folktronica", "stomp and holler", "new weird america"],
            rejects: ["folk metal"],
            searches: ["folk", "indie folk", "freak folk", "chamber folk", "stomp and holler",
                       "americana", "folk rock", "contemporary folk", "anti-folk",
                       "psychedelic folk", "neofolk", "traditional folk", "british folk",
                       "new weird america", "singer-songwriter", "modern folk rock"]
        ),
        Spec(
            names: ["Jazz"],
            accepts: ["jazz", "bebop", "hard bop", "post bop", "big band"],
            rejects: ["jazz rap", "jazz hip hop", "jazz house", "jazz metal"],
            searches: ["jazz", "contemporary jazz", "jazz fusion", "nu jazz", "free jazz",
                       "spiritual jazz", "avant-garde jazz", "hard bop", "cool jazz", "bebop",
                       "modern jazz", "uk contemporary jazz", "jazz trio", "vocal jazz",
                       "jazz piano", "experimental jazz", "chamber jazz"]
        ),
        Spec(
            names: ["Blues"],
            accepts: ["blues"],
            rejects: [],
            searches: ["blues", "modern blues", "blues rock", "electric blues", "delta blues",
                       "chicago blues", "soul blues", "texas blues", "country blues",
                       "modern blues rock", "traditional blues", "acoustic blues", "british blues"]
        ),
        Spec(
            names: ["Classical"],
            accepts: ["classical", "baroque", "opera", "early music", "orchestra", "orchestral",
                      "chamber music", "string quartet", "choral", "minimalism", "neoclassical"],
            rejects: ["baroque pop", "neoclassical metal", "neo classical metal"],
            searches: ["classical", "contemporary classical", "neoclassical", "modern classical",
                       "early music", "baroque", "classical piano", "string quartet",
                       "minimalism", "post-minimalism", "orchestral", "choral", "opera",
                       "21st century classical", "classical performance"]
        ),
        Spec(
            names: ["Metal"],
            accepts: ["metal", "metalcore", "deathcore", "grindcore", "mathcore", "djent",
                      "sludge", "thrash", "nwobhm"],
            rejects: [],
            searches: ["metal", "black metal", "death metal", "doom metal", "sludge metal",
                       "progressive metal", "metalcore", "stoner metal", "thrash metal",
                       "post-metal", "heavy metal", "atmospheric black metal", "deathcore",
                       "djent", "grindcore", "power metal", "melodic death metal",
                       "alternative metal"]
        ),
        Spec(
            names: ["Punk"],
            accepts: ["punk", "post-hardcore", "melodic hardcore", "crust", "oi", "riot grrrl"],
            rejects: [],
            searches: ["punk", "hardcore punk", "post-punk", "pop punk", "skate punk",
                       "garage punk", "punk rock", "art punk", "egg punk", "crust punk",
                       "melodic hardcore", "post-hardcore", "street punk"]
        ),
        Spec(
            names: ["Rock"],
            accepts: ["rock", "krautrock", "rockabilly", "grunge", "shoegaze", "britpop"],
            rejects: [],
            searches: ["rock", "indie rock", "garage rock", "psychedelic rock", "alternative rock",
                       "stoner rock", "noise rock", "post-rock", "math rock", "art rock",
                       "blues rock", "hard rock", "modern rock", "classic rock", "shoegaze",
                       "grunge", "surf rock", "space rock", "experimental rock"]
        ),
        Spec(
            names: ["Indie"],
            accepts: ["indie", "indietronica", "bedroom pop"],
            rejects: [],
            searches: ["indie", "indie rock", "indie pop", "indie folk", "bedroom pop",
                       "indietronica", "modern indie", "lo-fi indie", "indie garage rock",
                       "indie surf", "indie psych", "indie punk", "indie soul", "indie r&b"]
        ),
        Spec(
            names: ["Alternative"],
            accepts: ["alternative", "alt z", "alt rock", "grunge", "post-grunge"],
            rejects: [],
            searches: ["alternative", "alternative rock", "modern alternative rock",
                       "alternative pop", "alternative dance", "alt z", "grunge", "post-grunge",
                       "alternative metal", "alternative hip hop", "alternative r&b"]
        ),
        Spec(
            names: ["Pop"],
            accepts: ["pop", "synthpop", "electropop", "hyperpop", "britpop", "europop"],
            rejects: ["pop punk", "pop rap", "pop emo"],
            searches: ["pop", "indie pop", "bedroom pop", "dream pop", "art pop", "dance pop",
                       "electropop", "synthpop", "chamber pop", "hyperpop", "modern indie pop",
                       "power pop", "baroque pop", "pop soul"]
        ),
    ]

    // MARK: - Exclusions

    private struct ExclusionGroup {
        let phrases: [[String]]
        let except: [[String]]
    }

    private static func group(_ phrases: [String], except: [String] = []) -> ExclusionGroup {
        ExclusionGroup(phrases: phrases.map(tokens), except: except.map(tokens))
    }

    /// Genres kept out of every deck unless the user picked them.
    private static let systemExclusions: [ExclusionGroup] = [
        // Holiday music
        group(["christmas", "xmas", "holiday", "halloween", "easter", "valentines",
               "thanksgiving", "hanukkah", "kwanzaa", "new year"]),
        // Children's music
        group(["children", "childrens", "kids", "nursery", "lullaby", "disney", "cartoon"]),
        // Soundtracks, stage and game music
        group(["soundtrack", "movie", "show tunes", "broadway", "musical", "video game", "vgm",
               "game", "ost"]),
        // Anime
        group(["anime", "otacore", "vocaloid"]),
        // Religious
        group(["christian", "gospel", "worship", "ccm", "praise", "islamic", "religious",
               "hymns", "devotional", "nasheed"]),
        // Latin ("tropical house" is EDM, not Latin)
        group(["latin", "latino", "reggaeton", "spanish", "espanol", "musica", "salsa",
               "bachata", "cumbia", "merengue", "banda", "mariachi", "ranchera", "norteno",
               "corrido", "corridos", "sierreno", "vallenato", "dembow", "perreo", "mexicana",
               "mexican", "sertanejo", "pagode", "forro", "mpb", "tropical", "urbano"],
              except: ["tropical house"]),
    ]
}
