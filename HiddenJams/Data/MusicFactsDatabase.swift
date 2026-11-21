//
//  MusicFactsDatabase.swift
//  HiddenJams
//
//  Music facts shown while we dig (loading screen). Statements only, never
//  quiz questions (build 88 feedback). Every fact was checked against a
//  reputable source; see design-research/build88-fixes/FUNFACTS_SOURCES.md
//  in the design workspace. Add a fact only with a source.
//

import Foundation

struct MusicFactsDatabase {
    static let allFacts: [String] = [
        "A John Cage organ piece began playing in Halberstadt, Germany, in 2001. It's due to end in 2640.",
        "Bone and ivory flutes found in caves in southern Germany are at least 35,000 years old.",
        "Chuck Berry's \"Johnny B. Goode\" is headed into interstellar space on NASA's Voyager Golden Record.",
        "Freddie Mercury was born Farrokh Bulsara in Zanzibar.",
        "\"Smells Like Teen Spirit\" is named after a deodorant called Teen Spirit.",
        "Shel Silverstein, the children's author, wrote Johnny Cash's hit \"A Boy Named Sue.\"",
        "Dolly Parton wrote \"Jolene\" and \"I Will Always Love You\" on the same day.",
        "Michael Jackson's Thriller was already the best-selling album of all time by early 1984.",
        "Pink Floyd's The Dark Side of the Moon has spent 997 weeks on the Billboard album chart.",
        "The theremin is played without being touched. Your hands shape the sound in the air.",
        "Beethoven was almost completely deaf when he composed his Ninth Symphony.",
        "\"Happy Birthday to You\" only entered the US public domain in 2016, after a court ruling.",
        "The last piano chord of the Beatles' \"A Day in the Life\" rings out for over forty seconds.",
        "The Roland TR-808 drum machine flopped on release in 1980, then became the heartbeat of hip-hop.",
        "The \"Amen break,\" a seven-second drum break from 1969, is one of the most sampled recordings ever.",
        "Mozart wrote his first symphony at the age of eight.",
        "\"Bohemian Rhapsody\" doesn't have a chorus.",
        "\"Stairway to Heaven\" was never released as a commercial single in the US.",
        "Phil Collins played both Live Aid shows in one day: London, then Philadelphia by Concorde.",
        "\"Video Killed the Radio Star\" was the first video MTV ever played, at 12:01 a.m. on August 1, 1981.",
        "On his debut album For You, Prince sang every vocal and played every instrument.",
        "The \"Lady Blunt\" Stradivarius violin sold for about $15.9 million at auction.",
        "The Rolling Stones took their name from a Muddy Waters song, \"Rollin' Stone.\"",
        "Paul McCartney's working title for \"Yesterday\" was \"Scrambled Eggs.\"",
        "Billie Eilish's debut album was produced in her brother Finneas's small bedroom studio.",
        "\"All I Want for Christmas Is You\" first hit No. 1 on the Hot 100 in 2019, 25 years after its release.",
        "Every Steinway grand piano has more than 12,000 individual parts.",
        "Jimi Hendrix mostly played right-handed guitars flipped upside down and restrung for his left hand.",
        "More than 460,000 people showed up to Woodstock in 1969."
    ]

    /// Returns all facts shuffled randomly
    static func getShuffledFacts() -> [String] {
        return allFacts.shuffled()
    }

    /// Returns a specific number of random facts
    static func getRandomFacts(count: Int) -> [String] {
        return Array(allFacts.shuffled().prefix(count))
    }
}
