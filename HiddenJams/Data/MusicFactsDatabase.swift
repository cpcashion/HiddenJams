//
//  MusicFactsDatabase.swift
//  HiddenJams
//
//  Comprehensive database of music facts and trivia
//

import Foundation

struct MusicFactsDatabase {
    static let allFacts: [String] = [
        // Historical Facts
        "The world's longest concert started in 2001 and is scheduled to last 639 years.",
        "Mozart sold more CDs than Beyoncé in 2016 due to a massive box set release.",
        "Archaeologists found a 40,000-year-old flute made from bird bone, the oldest known instrument.",
        "Beethoven composed his greatest masterpieces after going completely deaf.",
        "The Beatles used the word 'love' 613 times throughout their discography.",
        "Jimi Hendrix, Janis Joplin, and Jim Morrison all tragically died at age 27.",
        "Canadians were the first to see the music video for 'Video Killed the Radio Star' on MTV.",
        "AC/DC's 'Back in Black' remains the second best-selling album of all time.",
        "Pink Floyd's 'The Dark Side of the Moon' charted on the Billboard 200 for over 14 years.",
        "The longest song ever recorded, 'The Rise and Fall of Bossanova', lasts 13 hours and 23 minutes.",
        
        // Scientific Facts
        "Neuroscience shows music stimulates the same brain regions as food and intimacy.",
        "The 'chills' you feel from music are a result of dopamine release in the striatum.",
        "Your heartbeat naturally synchronizes with the tempo of the music you listen to.",
        "Cyclists pedal faster and conserve more energy when listening to music.",
        "Studies suggest plants grow faster when exposed to music, particularly heavy metal.",
        "Dairy cows yield more milk when listening to relaxing, slow-tempo music.",
        "Listening to music is one of the few activities that utilizes the entire brain.",
        "Learning a musical instrument increases IQ by an average of 7 points.",
        "Music therapy reduces stress hormones like cortisol by up to 65%.",
        "Pre-operative music listening can reduce patient anxiety more effectively than medication.",
        
        // Instrument Facts
        "Leo Fender, inventor of the Stratocaster, never learned how to play guitar.",
        "A Stradivarius violin sold for $16 million, making it the most expensive instrument.",
        "A standard piano contains over 12,000 individual parts, with 10,000 moving pieces.",
        "The musical piece 'Organ²/ASLSP' is currently being played and will finish in the year 2640.",
        "Bagpipes were historically crafted from the distinct hides of sheep or goats.",
        "The accordion was patented in 1829 in Vienna, not associated with France originally.",
        "Grand pianos hold strings under a combined tension of roughly 30 tons.",
        "The largest playable guitar in the world is 43 feet long.",
        "The theremin is unique as the only instrument played without physical contact.",
        "The world's oldest playable organ, built in 1435, still resides in Switzerland.",
        
        // Genre Facts
        "Metal music has fractured into over 1,300 distinct sub-genres.",
        "Hip-hop has surpassed rock as the most popular music genre in the United States.",
        "Jazz was historically banned in some regimes for being considered rebellious.",
        "Country music went by the name 'hillbilly music' until the industry rebranded in 1949.",
        "Modern K-Pop originated in the 1990s, blending Korean culture with Western sounds.",
        "The term 'Disco' comes from the French word 'discothèque', meaning library of records.",
        "Reggae emerged in Jamaica in the late 1960s, evolving from ska and rocksteady.",
        "Punk rock defined itself by short, fast-paced songs typically under three minutes.",
        "Classic blues music creates its signature sound using a 12-bar chord progression.",
        "Major EDM festivals now attract over 400,000 attendees over a single weekend.",
        
        // Artist Facts
        "Prince played 27 different instruments on his debut album.",
        "Elvis Presley was an interpreter and performer who never wrote his own songs.",
        "Michael Jackson's 'Thriller' remains the best-selling album in history.",
        "Bob Marley performed a concert two days after surviving a shooting attempt.",
        "Lady Gaga wrote her hit 'Just Dance' in roughly ten minutes.",
        "Eminem holds a record for rapping 97 words in a 15-second verse.",
        "Freddie Mercury was born Farrokh Bulsara on the island of Zanzibar.",
        "Nirvana's 'Smells Like Teen Spirit' was accidentally named after a deodorant brand.",
        "Shel Silverstein, the children's author, wrote Johnny Cash's 'A Boy Named Sue'.",
        "Dolly Parton wrote 'I Will Always Love You' and 'Jolene' during the same writing session.",
        
        // Technical Facts
        "A vast majority of pop songs are written in C Major or A Minor for simplicity.",
        "Average song duration has dropped from nearly 4 minutes in the 90s to 3:30 today.",
        "Vinyl records are the only physical music format experiencing consistent sales growth.",
        "Spotify's catalog strictly exceeds 100 million tracks.",
        "The human ear is capable of distinguishing over one trillion distinct sounds.",
        "True perfect pitch is a rare ability found in only 1 in 10,000 people.",
        "The loudest recorded sound was the Krakatoa eruption, estimated at 310 decibels.",
        "Streaming now accounts for over 84% of total music industry revenue in the US.",
        "World record holders can rap over 400 syllables in under a minute.",
        "Auto-Tune technology was originally developed to analyze seismic data for oil drilling.",
        
        // Cultural Facts
        "Voyager 1 and 2 carry a Golden Record with music from Earth into deep space.",
        "Finland boasts more heavy metal bands per capita than any other nation.",
        "Monaco is one of the few countries with a national anthem that has no official lyrics.",
        "The tune for the ice cream truck song 'Turkey in the Straw' dates back to the 1820s.",
        "Warner Chappell Music earned millions from 'Happy Birthday' until it entered the public domain.",
        "The Macarena remains one of the most successful international dance songs of all time.",
        "Group singing triggers the release of oxytocin, known as the bonding hormone.",
        "Music therapy is increasingly used to assist patients with Alzheimer's and Parkinson's.",
        "Summerfest in Milwaukee holds the title for the world's largest music festival.",
        "The longest DJ set recorded lasted an incredible 240 hours.",
        
        // App-Specific Progress Statements
        "Our AI is identifying your unique taste profile.",
        "We are scanning for hidden gems in obscure genres.",
        "The system is cross-referencing with 100,000+ obscure artists.",
        "Analyzing beat patterns and energy levels in your library.",
        "Filtering out the mainstream noise to find the gold.",
        "Locating tracks with under 1,000 streams tailored to you.",
        "Searching for micro-genres you have likely never heard of.",
        "Comparing your listening history against millions of data points.",
        "Detecting audio features like Danceability, Energy, and Valence.",
        "Checking specifically for seasonal tracks to exclude.",
        "Mapping your musical DNA to find new connections.",
        "Discovering artists from around the globe to broaden your horizons.",
        "Analyzing tempo, key, and time signatures for perfect flow.",
        "Finding the perfect match for your current musical vibe.",
        "Exploring the long tail of music discovery for rare finds.",
        "Calculating obscurity scores for every track in the connection graph.",
        "Matching your genre preferences with hidden artist catalogs.",
        "Building your personalized recommendation engine from scratch.",
        "Filtering candidates by artist popularity and follower counts.",
        "Searching through decades of underground releases for timeless tracks."
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
