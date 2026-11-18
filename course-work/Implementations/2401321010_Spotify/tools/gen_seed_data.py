# -*- coding: utf-8 -*-
"""Generates database/03_seed_data.sql - sample data for SpotifyDB.

The catalogue (artists, albums, tracks) is real; users, subscriptions, payments,
streams, likes, follows and playlists are simulated with a fixed random seed,
so every run produces exactly the same file.

Run:  python tools/gen_seed_data.py
"""
import bisect
import datetime as dt
import math
import os
import random

R = random.Random(2401321010)
START = dt.date(2025, 1, 1)          # first day with listening data
END = dt.date(2026, 10, 31)          # last day with data
N_USERS = 300
N_STREAMS = 25000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'database', '03_seed_data.sql')

# ---------------------------------------------------------------------------
# Reference data
# ---------------------------------------------------------------------------
COUNTRIES = [  # name, ISO, region, share of users
    ('Bulgaria', 'BG', 'Eastern Europe', 30), ('Romania', 'RO', 'Eastern Europe', 5),
    ('Greece', 'GR', 'Southern Europe', 5), ('Turkey', 'TR', 'Western Asia', 4),
    ('Germany', 'DE', 'Western Europe', 8), ('France', 'FR', 'Western Europe', 6),
    ('United Kingdom', 'GB', 'Northern Europe', 8), ('Spain', 'ES', 'Southern Europe', 5),
    ('Italy', 'IT', 'Southern Europe', 5), ('Netherlands', 'NL', 'Western Europe', 3),
    ('Sweden', 'SE', 'Northern Europe', 3), ('United States', 'US', 'North America', 9),
    ('Brazil', 'BR', 'Latin America', 3), ('Mexico', 'MX', 'Latin America', 2),
    ('South Korea', 'KR', 'East Asia', 2), ('Japan', 'JP', 'East Asia', 2),
]
DEVICES = [  # type, platform, share
    ('Mobile', 'Android', 34), ('Mobile', 'iOS', 26), ('Desktop', 'Windows', 14), ('Desktop', 'macOS', 6),
    ('Web', 'Browser', 8), ('Tablet', 'iPadOS', 4), ('Smart speaker', 'Google Home', 4), ('TV', 'Android TV', 4),
]
GENRES = [
    ('Pop', 'Popular mainstream music'), ('Rock', 'Guitar-driven rock music'), ('Hip-Hop', 'Rap and hip-hop'),
    ('R&B', 'Rhythm and blues'), ('Electronic', 'Electronic music'), ('Dance', 'Dance and club music'),
    ('Indie', 'Independent music'), ('Alternative', 'Alternative music'), ('Metal', 'Heavy metal'),
    ('Jazz', 'Jazz'), ('Latin', 'Latin and reggaeton'), ('Reggae', 'Reggae'),
    ('Soundtrack', 'Film and game scores'), ('Soul', 'Soul music'), ('Folk', 'Folk and acoustic'),
    ('K-Pop', 'Korean pop music'), ('Pop-Folk', 'Bulgarian pop-folk'), ('Classical', 'Classical and neoclassical'),
]
PLANS = [  # name, price, max accounts, has ads, offline, skips per hour
    ('Free', 0.00, 1, 1, 0, 6), ('Premium Individual', 7.98, 1, 0, 1, None),
    ('Premium Duo', 10.99, 2, 0, 1, None), ('Premium Family', 13.99, 6, 0, 1, None),
    ('Premium Student', 3.99, 1, 0, 1, None),
]
PRICE = {p[0]: p[1] for p in PLANS}


def T(title, dur=None, feat=None, explicit=False):
    return {'title': title, 'dur': dur, 'feat': feat or [], 'explicit': explicit}


def X(title, dur=None, feat=None):          # explicit track
    return T(title, dur, feat, True)


# artist: (name, bio, [genres], popularity, home, [albums])
# album : (title, type, release date or None = random, label, [tracks], optional [genres])
CATALOG = [
    ('The Weeknd', 'Canadian singer, songwriter and producer.', ['R&B', 'Pop'], 10, None, [
        ('Starboy', 'Album', '2016-11-25', 'XO / Republic', [
            X('Starboy', 230, ['Daft Punk']), X('Party Monster', 249), T('False Alarm', 220), X('Reminder', 218),
            T('Secrets', 265), T('Stargirl Interlude', 111, ['Lana Del Rey']), T('Die for You', 260),
            T('I Feel It Coming', 269, ['Daft Punk'])]),
        ('After Hours', 'Album', '2020-03-20', 'XO / Republic', [
            T('Alone Again', 250), T('Too Late', 239), T('Hardest to Love', 211), X('Heartless', 198),
            T('Blinding Lights', 200), T('In Your Eyes', 237), T('Save Your Tears', 215), T('After Hours', 361)]),
    ]),
    ('Lana Del Rey', 'American singer-songwriter.', ['Alternative', 'Pop'], 8, None, [
        ('Born to Die', 'Album', '2012-01-27', 'Interscope / Polydor', [
            T('Born to Die', 286), T('Off to the Races', 300), T('Blue Jeans', 209), T('Video Games', 282),
            T('Diet Mountain Dew', 223), T('National Anthem', 231), T('Dark Paradise', 243),
            T('Summertime Sadness', 265)]),
        ('Lust for Life', 'Album', '2017-07-21', 'Interscope / Polydor', [
            T('Love', 272), T('Lust for Life', 264, ['The Weeknd']), T('13 Beaches', 295), T('Cherry', 180),
            T('White Mustang', 164), T('In My Feelings', 238), T('Heroin', 355), T('Get Free', 334)]),
    ]),
    ('aespa', 'South Korean girl group formed by SM Entertainment in 2020.', ['K-Pop', 'Dance'], 9, 'KR', [
        ('MY WORLD', 'EP', '2023-05-08', 'SM Entertainment', [
            T('Welcome to MY World', 207, ['nævis']), T('Spicy', 197), T('Salty & Sweet', 202), T('Thirsty', 193),
            T("I'm Unhappy", 206), T("'Til We Meet Again", 218)]),
        ('Drama', 'EP', '2023-11-10', 'SM Entertainment', [
            T('Drama', 215), T('Trick or Trick', 175), T("Don't Blink", 169), T('Hot Air Balloon', 199),
            T('YOLO', 189), T('You', 203), T('Better Things', 203)]),
        ('Armageddon', 'Album', '2024-05-27', 'SM Entertainment', [
            T('Supernova', 179), T('Armageddon', 197), T('Set the Tone', 203), T('Mine', 194), T('Licorice', 159),
            T('Bahama', 191), T('Long Chat (#♥)', 196), T('Prologue', 195), T('Live My Life', 160),
            T('Melody', 188)]),
        ('Whiplash', 'EP', '2024-10-21', 'SM Entertainment', [
            T('Whiplash', 183), T('Kill It', 200), T('Flights, Not Feelings', 182), T('Pink Hoodie', 147),
            T('Flowers', 191), T('Just Another Girl', 184)]),
    ]),
    ('Simona', 'Bulgarian pop-folk singer.', ['Pop-Folk', 'Pop'], 7, 'BG', [
        ('Prahosmukachka', 'Single', None, None, [T('Prahosmukachka')]),
        ('Katinara', 'Single', None, None, [T('Katinara')]),
        ('Deja vu', 'Single', None, None, [T('Deja vu')]),
        ('Momiche ot led', 'Single', None, None, [T('Momiche ot led')]),
    ]),
    ('Alex & Vladi', 'Bulgarian pop duo.', ['Pop', 'Dance'], 6, 'BG', [
        ('Samo za svobodni', 'Single', None, None, [T('Samo za svobodni')]),
        ('Superman', 'Single', None, None, [T('Superman')]),
        ('Merak', 'Single', None, None, [T('Merak')]),
    ]),
    ('Dua Lipa', 'English-Albanian pop singer.', ['Pop', 'Dance'], 8, None, [
        ('Future Nostalgia', 'Album', '2020-03-27', 'Warner', [
            T('Future Nostalgia'), T("Don't Start Now", 183), T('Cool'), T('Physical', 194), T('Levitating', 203),
            T('Pretty Please'), T('Hallucinate'), T('Love Again'), T('Break My Heart', 221)]),
    ]),
    ('Taylor Swift', 'American singer-songwriter.', ['Pop', 'Folk'], 10, None, [
        ('1989', 'Album', '2014-10-27', 'Big Machine', [
            T('Welcome to New York'), T('Blank Space', 231), T('Style', 231), T('Out of the Woods'),
            T('Shake It Off', 219), T('Bad Blood'), T('Wildest Dreams', 220), T('Clean')]),
        ('folklore', 'Album', '2020-07-24', 'Republic', [
            T('the 1'), T('cardigan', 239), T('the last great american dynasty'), T('exile', 285, ['Bon Iver']),
            T('my tears ricochet'), T('mirrorball'), T('august', 261), T('betty')], ['Folk', 'Indie']),
    ]),
    ('Ed Sheeran', 'English singer-songwriter.', ['Pop', 'Folk'], 8, None, [
        ('÷ (Divide)', 'Album', '2017-03-03', 'Asylum / Atlantic', [
            T('Eraser'), T('Castle on the Hill', 261), T('Dive'), T('Shape of You', 233), T('Perfect', 263),
            T('Galway Girl', 170), T('Happier'), T('Supermarket Flowers')]),
    ]),
    ('Billie Eilish', 'American singer-songwriter.', ['Pop', 'Alternative'], 8, None, [
        ('dont smile at me', 'EP', '2017-08-11', 'Darkroom / Interscope', [
            T('COPYCAT'), T('idontwannabeyouanymore'), T('my boy'), T('watch'), T('party favor'), T('bellyache'),
            T('ocean eyes', 200), T('hostage')]),
        ('WHEN WE ALL FALL ASLEEP, WHERE DO WE GO?', 'Album', '2019-03-29', 'Darkroom / Interscope', [
            T('bad guy', 194), T('xanny'), T('you should see me in a crown'), T('all the good girls go to hell'),
            T('wish you were gay'), T("when the party's over", 196), T('bury a friend'), T('ilomilo')]),
    ]),
    ('Drake', 'Canadian rapper and singer.', ['Hip-Hop', 'R&B'], 8, None, [
        ('Scorpion', 'Album', '2018-06-29', 'Young Money / Cash Money / Republic', [
            X('Nonstop'), X('Elevate'), X('Emotionless'), X("God's Plan", 198), X('Mob Ties'), X('Nice for What', 210),
            X('In My Feelings', 217), X("Don't Matter to Me")]),
    ]),
    ('Kendrick Lamar', 'American rapper.', ['Hip-Hop'], 7, None, [
        ('DAMN.', 'Album', '2017-04-14', 'TDE / Aftermath / Interscope', [
            X('DNA.', 185), X('YAH.'), X('ELEMENT.'), X('FEEL.'), X('LOYALTY.', 227, ['Rihanna']), X('PRIDE.'),
            X('HUMBLE.', 177), X('LOVE.')]),
    ]),
    ('Eminem', 'American rapper.', ['Hip-Hop'], 7, None, [
        ('The Eminem Show', 'Album', '2002-05-26', 'Shady / Aftermath / Interscope', [
            X('White America'), X('Business'), X("Cleanin' Out My Closet"), X('Without Me', 290),
            X('Sing for the Moment'), X('Superman'), X("Hailie's Song"), X("'Till I Collapse", 297)]),
    ]),
    ('Post Malone', 'American rapper and singer.', ['Hip-Hop', 'Pop'], 6, None, [
        ("Hollywood's Bleeding", 'Album', '2019-09-06', 'Republic', [
            X("Hollywood's Bleeding"), X('Saint-Tropez'), X('Enemies'), T('Allergic'), T('Circles', 215),
            X('Goodbyes'), T('Sunflower', 158, ['Swae Lee']), X('Wow.')]),
    ]),
    ('Rihanna', 'Barbadian singer.', ['Pop', 'R&B'], 7, None, [
        ('Loud', 'Album', '2010-11-12', 'Def Jam', [
            X('S&M'), T("What's My Name?", 263, ['Drake']), T('Cheers (Drink to That)'), T('Fading'),
            T('Only Girl (In the World)', 235), T('California King Bed'), T('Man Down'), T('Raining Men')]),
    ]),
    ('Bruno Mars', 'American singer and songwriter.', ['Pop', 'R&B'], 7, None, [
        ('Unorthodox Jukebox', 'Album', '2012-12-07', 'Atlantic', [
            T('Young Girls'), T('Locked Out of Heaven', 233), X('Gorilla'), T('Treasure', 178), T('Moonshine'),
            T('When I Was Your Man', 213), T('Natalie'), T('If I Knew')]),
    ]),
    ('Adele', 'English singer-songwriter.', ['Pop', 'Soul'], 7, None, [
        ('21', 'Album', '2011-01-24', 'XL / Columbia', [
            T('Rolling in the Deep', 228), T('Rumour Has It'), T('Turning Tables'), T("Don't You Remember"),
            T('Set Fire to the Rain', 242), T("He Won't Go"), T('One and Only'), T('Someone Like You', 285)]),
    ]),
    ('Harry Styles', 'English singer.', ['Pop'], 6, None, [
        ("Harry's House", 'Album', '2022-05-20', 'Columbia / Erskine', [
            T('Music for a Sushi Restaurant'), T('Late Night Talking'), T('Grapejuice'), T('As It Was', 167),
            T('Daylight'), T('Little Freak'), T('Matilda'), T('Satellite')]),
    ]),
    ('Miley Cyrus', 'American singer.', ['Pop'], 5, None, [
        ('Flowers', 'Single', '2023-01-12', 'Columbia', [T('Flowers', 200)]),
    ]),
    ('Coldplay', 'British rock band.', ['Alternative', 'Rock'], 8, None, [
        ('Parachutes', 'Album', '2000-07-10', 'Parlophone', [
            T("Don't Panic"), T('Shiver'), T('Spies'), T('Sparks'), T('Yellow', 269), T('Trouble')]),
        ('A Rush of Blood to the Head', 'Album', '2002-08-26', 'Parlophone', [
            T('Politik'), T('In My Place'), T('God Put a Smile upon Your Face'), T('The Scientist', 309),
            T('Clocks', 307), T('Daylight'), T('Green Eyes'), T('Warning Sign')]),
    ]),
    ('Imagine Dragons', 'American pop rock band.', ['Rock', 'Alternative'], 6, None, [
        ('Night Visions', 'Album', '2012-09-04', 'Interscope / KIDinaKORNER', [
            T('Radioactive', 186), T('Tiptoe'), T("It's Time"), T('Demons', 177), T('On Top of the World'),
            T('Amsterdam'), T('Hear Me'), T('Bleeding Out')]),
    ]),
    ('Arctic Monkeys', 'English rock band.', ['Indie', 'Rock'], 6, None, [
        ('AM', 'Album', '2013-09-09', 'Domino', [
            T('Do I Wanna Know?', 272), T('R U Mine?'), T('One for the Road'), T('Arabella'),
            T("Why'd You Only Call Me When You're High?", 161), T('Snap Out of It'), T('Knee Socks'),
            T('I Wanna Be Yours', 184)]),
    ]),
    ('Queen', 'British rock band.', ['Rock'], 7, None, [
        ('A Night at the Opera', 'Album', '1975-11-21', 'EMI', [
            T('Death on Two Legs'), T("You're My Best Friend"), T("'39"), T('Love of My Life'),
            T('Bohemian Rhapsody', 354), T("I'm in Love with My Car")]),
        ('News of the World', 'Album', '1977-10-28', 'EMI', [
            T('We Will Rock You', 122), T('We Are the Champions', 179), T('Spread Your Wings'), T("It's Late")]),
    ]),
    ('AC/DC', 'Australian rock band.', ['Rock', 'Metal'], 5, None, [
        ('Back in Black', 'Album', '1980-07-25', 'Atlantic', [
            T('Hells Bells'), T('Shoot to Thrill'), T('Back in Black', 255), T('You Shook Me All Night Long', 210),
            T('Have a Drink on Me'), T("Rock and Roll Ain't Noise Pollution")]),
    ]),
    ('Metallica', 'American heavy metal band.', ['Metal', 'Rock'], 5, None, [
        ('Metallica', 'Album', '1991-08-12', 'Elektra', [
            T('Enter Sandman', 331), T('Sad but True'), T('Holier Than Thou'), T('The Unforgiven'),
            T('Wherever I May Roam'), T('Nothing Else Matters', 388)]),
    ]),
    ('Nirvana', 'American rock band.', ['Rock', 'Alternative'], 5, None, [
        ('Nevermind', 'Album', '1991-09-24', 'DGC', [
            T('Smells Like Teen Spirit', 301), T('In Bloom'), T('Come as You Are', 219), T('Breed'), T('Lithium'),
            T('Polly'), T('Drain You'), T('Something in the Way')]),
    ]),
    ('Linkin Park', 'American rock band.', ['Rock', 'Metal'], 6, None, [
        ('Hybrid Theory', 'Album', '2000-10-24', 'Warner Bros.', [
            T('Papercut'), T('One Step Closer'), T('With You'), T('Points of Authority'), T('Crawling'),
            T('Runaway'), T('In the End', 216), T('Pushing Me Away')]),
    ]),
    ('Daft Punk', 'French electronic music duo.', ['Electronic', 'Dance'], 6, None, [
        ('Discovery', 'Album', '2001-03-12', 'Virgin', [
            T('One More Time', 320), T('Aerodynamic'), T('Digital Love'), T('Harder, Better, Faster, Stronger', 224),
            T('Something About Us'), T('Veridis Quo')]),
        ('Random Access Memories', 'Album', '2013-05-17', 'Columbia', [
            T('Give Life Back to Music'), T('The Game of Love'), T('Giorgio by Moroder', 544), T('Instant Crush', 337),
            T('Lose Yourself to Dance', 353, ['Pharrell Williams']), T('Get Lucky', 369, ['Pharrell Williams']),
            T("Doin' It Right"), T('Contact')]),
    ]),
    ('Avicii', 'Swedish DJ and producer.', ['Electronic', 'Dance'], 6, None, [
        ('True', 'Album', '2013-09-13', 'PRMD / Universal', [
            T('Wake Me Up', 247), T('You Make Me'), T('Hey Brother', 255), T('Addicted to You'), T('Dear Boy'),
            T('Liar Liar'), T('Shame on Me'), T('Lay Me Down')]),
    ]),
    ('Calvin Harris', 'Scottish DJ and producer.', ['Dance', 'Electronic'], 5, None, [
        ('18 Months', 'Album', '2012-10-26', 'Columbia / Fly Eye', [
            T('Bounce'), T('Feel So Close', 206), T('We Found Love', 215, ['Rihanna']), T('Sweet Nothing'),
            T('I Need Your Love'), T("Let's Go"), T('Thinking About You'), T('Drinking from the Bottle')]),
    ]),
    ('Bad Bunny', 'Puerto Rican rapper and singer.', ['Latin'], 7, 'LATAM', [
        ('Un Verano Sin Ti', 'Album', '2022-05-06', 'Rimas', [
            T('Moscow Mule', 245), X('Después de la Playa'), X('Me Porto Bonito', 178), X('Tití Me Preguntó', 243),
            T('Un Ratito'), T('Neverita'), X('Efecto'), T('Ojitos Lindos')]),
    ]),
    ('Shakira', 'Colombian singer.', ['Latin', 'Pop'], 6, 'LATAM', [
        ('Laundry Service', 'Album', '2001-11-13', 'Epic', [
            T('Objection (Tango)'), T('Underneath Your Clothes'), T('Whenever, Wherever', 196), T('Rules'),
            T('The One'), T('Te Dejo Madrid'), T('Que Me Quedes Tú'), T('Eyes Like Yours')]),
    ]),
    ('Bob Marley & The Wailers', 'Jamaican reggae band.', ['Reggae'], 4, None, [
        ('Exodus', 'Album', '1977-06-03', 'Island', [
            T('Natural Mystic'), T('Exodus', 456), T('Jamming'), T('Waiting in Vain'),
            T('Turn Your Lights Down Low'), T('Three Little Birds', 180), T('One Love / People Get Ready')]),
    ]),
    ('Miles Davis', 'American jazz trumpeter.', ['Jazz'], 2, None, [
        ('Kind of Blue', 'Album', '1959-08-17', 'Columbia', [
            T('So What', 562), T('Freddie Freeloader', 586), T('Blue in Green', 337), T('All Blues', 693),
            T('Flamenco Sketches', 566)]),
    ]),
    ('Hans Zimmer', 'German film score composer.', ['Soundtrack'], 3, None, [
        ('Interstellar (Original Motion Picture Soundtrack)', 'Album', '2014-11-17', 'WaterTower Music', [
            T('Dreaming of the Crash'), T('Cornfield Chase', 126), T('Dust'), T('Day One'), T('Stay'),
            T('Mountains'), T('S.T.A.Y.'), T("Where We're Going")]),
    ]),
    # featured guests on the albums above, each with one single of their own
    ('Pharrell Williams', 'American singer and producer.', ['Pop'], 3, None, [
        ('Happy', 'Single', '2013', None, [T('Happy', 233)])]),
    ('Bon Iver', 'American indie folk band.', ['Indie', 'Folk'], 2, None, [
        ('Skinny Love', 'Single', '2008', None, [T('Skinny Love', 238)])]),
    ('Swae Lee', 'American rapper and singer.', ['Hip-Hop'], 2, None, [
        ("Won't Be Late", 'Single', '2019', None, [T("Won't Be Late", 217, ['Drake'])])]),
    ('nævis', 'Virtual artist from the aespa universe.', ['K-Pop'], 2, 'KR', [
        ('Done', 'Single', '2024', None, [T('Done')])]),
]

# More artists, one well-known single each:
# (artist, [genres], popularity, home, title, release year, explicit, [featured artists])
SINGLES = [
    ('Ariana Grande', ['Pop', 'R&B'], 5, None, '7 rings', 2019, True, []),
    ('Justin Bieber', ['Pop', 'R&B'], 5, None, 'Peaches', 2021, True, []),
    ('Olivia Rodrigo', ['Pop'], 5, None, 'drivers license', 2021, True, []),
    ('Sabrina Carpenter', ['Pop'], 5, None, 'Espresso', 2024, False, []),
    ('Lady Gaga', ['Pop', 'Dance'], 5, None, 'Bad Romance', 2009, False, []),
    ('Katy Perry', ['Pop'], 4, None, 'Firework', 2010, False, []),
    ('Selena Gomez', ['Pop'], 4, None, 'Lose You to Love Me', 2019, False, []),
    ('Shawn Mendes', ['Pop'], 4, None, 'Stitches', 2015, False, []),
    ('Sia', ['Pop'], 4, None, 'Chandelier', 2014, False, []),
    ('Lorde', ['Pop', 'Alternative'], 3, None, 'Royals', 2013, False, []),
    ('Doja Cat', ['Pop', 'R&B'], 4, None, 'Say So', 2019, False, []),
    ('SZA', ['R&B'], 4, None, 'Kill Bill', 2022, True, []),
    ('Beyoncé', ['R&B', 'Pop'], 5, None, 'Halo', 2008, False, []),
    ('Michael Jackson', ['Pop'], 5, None, 'Billie Jean', 1983, False, []),
    ('Madonna', ['Pop'], 3, None, 'Like a Prayer', 1989, False, []),
    ('Britney Spears', ['Pop'], 4, None, 'Toxic', 2004, False, []),
    ('ABBA', ['Pop'], 4, None, 'Dancing Queen', 1976, False, []),
    ('Whitney Houston', ['Pop', 'Soul'], 3, None, 'I Wanna Dance with Somebody (Who Loves Me)', 1987, False, []),
    ('Elton John', ['Pop', 'Rock'], 3, None, 'Rocket Man', 1972, False, []),
    ('Sam Smith', ['Pop', 'Soul'], 3, None, 'Stay with Me', 2014, False, []),
    ('Charlie Puth', ['Pop'], 3, None, 'Attention', 2017, False, []),
    ('Lewis Capaldi', ['Pop'], 3, None, 'Someone You Loved', 2018, False, []),
    ('Tate McRae', ['Pop'], 3, None, 'greedy', 2023, False, []),
    ('Chappell Roan', ['Pop'], 3, None, 'Good Luck, Babe!', 2024, False, []),
    ('Benson Boone', ['Pop'], 3, None, 'Beautiful Things', 2024, False, []),
    ('Travis Scott', ['Hip-Hop'], 4, None, 'SICKO MODE', 2018, True, ['Drake']),
    ('Kanye West', ['Hip-Hop'], 4, None, 'Stronger', 2007, True, []),
    ('Jay-Z', ['Hip-Hop'], 3, None, 'Empire State of Mind', 2009, True, []),
    ('50 Cent', ['Hip-Hop'], 3, None, 'In da Club', 2003, True, []),
    ('Nicki Minaj', ['Hip-Hop', 'Pop'], 3, None, 'Super Bass', 2011, True, []),
    ('Cardi B', ['Hip-Hop', 'Latin'], 3, None, 'I Like It', 2018, True, ['Bad Bunny']),
    ('Frank Ocean', ['R&B'], 3, None, 'Thinkin Bout You', 2012, False, []),
    ('Childish Gambino', ['R&B', 'Hip-Hop'], 3, None, 'Redbone', 2016, True, []),
    ('Tyler, The Creator', ['Hip-Hop'], 3, None, 'EARFQUAKE', 2019, True, []),
    ('Snoop Dogg', ['Hip-Hop'], 3, None, "Drop It Like It's Hot", 2004, True, ['Pharrell Williams']),
    ('The Beatles', ['Rock', 'Pop'], 5, None, 'Hey Jude', 1968, False, []),
    ('Led Zeppelin', ['Rock'], 3, None, 'Stairway to Heaven', 1971, False, []),
    ('Pink Floyd', ['Rock'], 3, None, 'Wish You Were Here', 1975, False, []),
    ('The Rolling Stones', ['Rock'], 3, None, 'Paint It, Black', 1966, False, []),
    ("Guns N' Roses", ['Rock'], 3, None, "Sweet Child o' Mine", 1987, False, []),
    ('Red Hot Chili Peppers', ['Rock', 'Alternative'], 4, None, 'Californication', 2000, False, []),
    ('Foo Fighters', ['Rock', 'Alternative'], 3, None, 'Everlong', 1997, False, []),
    ('Green Day', ['Rock', 'Alternative'], 3, None, 'Boulevard of Broken Dreams', 2004, False, []),
    ('Radiohead', ['Alternative', 'Rock'], 3, None, 'Creep', 1992, True, []),
    ('Oasis', ['Rock', 'Alternative'], 3, None, 'Wonderwall', 1995, False, []),
    ('The Killers', ['Rock', 'Indie'], 4, None, 'Mr. Brightside', 2004, False, []),
    ('Muse', ['Rock', 'Alternative'], 3, None, 'Uprising', 2009, False, []),
    ('Twenty One Pilots', ['Alternative', 'Pop'], 3, None, 'Stressed Out', 2015, False, []),
    ('Tame Impala', ['Indie', 'Alternative'], 3, None, 'The Less I Know the Better', 2015, False, []),
    ('Måneskin', ['Rock'], 3, None, "Beggin'", 2017, False, []),
    ('Rammstein', ['Metal', 'Rock'], 3, None, 'Du hast', 1997, False, []),
    ('System of a Down', ['Metal', 'Rock'], 3, None, 'Chop Suey!', 2001, False, []),
    ('Iron Maiden', ['Metal'], 2, None, 'The Trooper', 1983, False, []),
    ('Scorpions', ['Rock'], 3, None, 'Wind of Change', 1991, False, []),
    ('Bon Jovi', ['Rock'], 3, None, "Livin' on a Prayer", 1986, False, []),
    ('David Guetta', ['Dance', 'Electronic'], 4, None, 'Titanium', 2011, False, ['Sia']),
    ('Martin Garrix', ['Electronic', 'Dance'], 3, None, 'Animals', 2013, False, []),
    ('The Chainsmokers', ['Dance', 'Pop'], 3, None, 'Closer', 2016, False, []),
    ('Kygo', ['Electronic', 'Dance'], 3, None, 'Firestone', 2014, False, []),
    ('Marshmello', ['Electronic', 'Dance'], 3, None, 'Happier', 2018, False, []),
    ('Swedish House Mafia', ['Electronic', 'Dance'], 3, None, "Don't You Worry Child", 2012, False, []),
    ('Tiësto', ['Electronic', 'Dance'], 3, None, 'The Business', 2020, False, []),
    ('Zedd', ['Electronic', 'Dance'], 2, None, 'Clarity', 2012, False, []),
    ('Alan Walker', ['Electronic'], 3, None, 'Faded', 2015, False, []),
    ('BTS', ['K-Pop', 'Pop'], 5, 'KR', 'Dynamite', 2020, False, []),
    ('BLACKPINK', ['K-Pop'], 5, 'KR', 'How You Like That', 2020, False, []),
    ('NewJeans', ['K-Pop'], 4, 'KR', 'Super Shy', 2023, False, []),
    ('LE SSERAFIM', ['K-Pop'], 3, 'KR', 'ANTIFRAGILE', 2022, False, []),
    ('IVE', ['K-Pop'], 3, 'KR', 'LOVE DIVE', 2022, False, []),
    ('Stray Kids', ['K-Pop', 'Hip-Hop'], 3, 'KR', "God's Menu", 2020, False, []),
    ('TWICE', ['K-Pop'], 3, 'KR', 'FANCY', 2019, False, []),
    ('Luis Fonsi', ['Latin', 'Pop'], 4, 'LATAM', 'Despacito', 2017, False, []),
    ('J Balvin', ['Latin'], 3, 'LATAM', 'Mi Gente', 2017, False, []),
    ('Karol G', ['Latin'], 3, 'LATAM', 'PROVENZA', 2022, False, []),
    ('Rosalía', ['Latin', 'Pop'], 3, 'LATAM', 'DESPECHÁ', 2022, False, []),
    ('Enrique Iglesias', ['Latin', 'Pop'], 3, 'LATAM', 'Bailando', 2014, False, []),
    ('Frank Sinatra', ['Jazz'], 2, None, 'Fly Me to the Moon', 1964, False, []),
    ('Louis Armstrong', ['Jazz'], 2, None, 'What a Wonderful World', 1967, False, []),
    ('Norah Jones', ['Jazz', 'Pop'], 2, None, "Don't Know Why", 2002, False, []),
    ('Ludovico Einaudi', ['Classical'], 2, None, 'Nuvole Bianche', 2004, False, []),
    ('Amy Winehouse', ['Soul', 'Jazz'], 3, None, 'Back to Black', 2006, False, []),
    ('Stevie Wonder', ['Soul'], 3, None, 'Superstition', 1972, False, []),
    ('Hozier', ['Indie', 'Soul'], 3, None, 'Take Me to Church', 2013, False, []),
    ('Mumford & Sons', ['Folk', 'Indie'], 2, None, 'Little Lion Man', 2009, True, []),
    ('Bob Dylan', ['Folk', 'Rock'], 2, None, 'Like a Rolling Stone', 1965, False, []),
    ('Sean Paul', ['Reggae', 'Dance'], 3, None, 'Temperature', 2005, False, []),
    ('Azis', ['Pop-Folk'], 4, 'BG', 'Sen Trope', 2011, False, []),
    ('Papi Hans', ['Pop'], 4, 'BG', 'Keks', 2018, False, []),
    ('Krisko', ['Hip-Hop', 'Pop'], 4, 'BG', 'Vidimo dovolen', 2014, False, []),
    ('DARA', ['Pop'], 4, 'BG', 'Thunder', 2022, False, []),
]
for _name, _genres, _pop, _home, _title, _year, _explicit, _feat in SINGLES:
    CATALOG.append((_name, None, _genres, _pop, _home,
                    [(_title, 'Single', str(_year), None, [T(_title, None, _feat, _explicit)])]))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def q(v):
    """SQL literal."""
    if v is None:
        return 'NULL'
    if isinstance(v, bool):
        return '1' if v else '0'
    if isinstance(v, (int, float)):
        return f'{v:.2f}' if isinstance(v, float) else str(v)
    if isinstance(v, dt.datetime):
        return "'" + v.strftime('%Y-%m-%d %H:%M:%S') + "'"
    if isinstance(v, dt.date):
        return "'" + v.isoformat() + "'"
    return "N'" + str(v).replace("'", "''") + "'"


def weighted(items, weights):
    return R.choices(items, weights=weights, k=1)[0]


def add_month(d):
    y, m = (d.year, d.month + 1) if d.month < 12 else (d.year + 1, 1)
    last = (dt.date(y + (m == 12), (m % 12) + 1, 1) - dt.timedelta(days=1)).day
    return dt.date(y, m, min(d.day, last))


def age_on(dob, day):
    return day.year - dob.year - ((day.month, day.day) < (dob.month, dob.day))


def rand_dt(day):
    hour = weighted(range(24), [2, 1, 1, 1, 1, 2, 4, 7, 9, 8, 7, 7, 8, 8, 7, 7, 8, 10, 12, 13, 13, 11, 8, 4])
    return dt.datetime(day.year, day.month, day.day, hour, R.randrange(60), R.randrange(60))


out = []


def emit(table, cols, rows, identity=False):
    """Multi-row INSERTs, at most 1000 rows per statement, one batch each."""
    if not rows:
        return
    if identity:
        out.append(f'SET IDENTITY_INSERT dbo.{table} ON;')
    for i in range(0, len(rows), 1000):
        chunk = rows[i:i + 1000]
        out.append(f'INSERT INTO dbo.{table} ({", ".join(cols)}) VALUES')
        out.append(',\n'.join('(' + ', '.join(q(v) for v in r) + ')' for r in chunk) + ';')
        if i + 1000 < len(rows):
            out.append('GO')
            if identity:
                out.append(f'SET IDENTITY_INSERT dbo.{table} ON;')
    if identity:
        out.append(f'SET IDENTITY_INSERT dbo.{table} OFF;')
    out.append('GO')
    out.append(f"PRINT '{table}: {len(rows)} rows';")
    out.append('GO')


# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------
genre_id = {g[0]: i + 1 for i, g in enumerate(GENRES)}
artist_id = {a[0]: i + 1 for i, a in enumerate(CATALOG)}
artists, albums, tracks, track_artists, track_genres = [], [], [], [], []
track_info = []        # dicts used by the simulation

for name, bio, genres, pop, home, albs in CATALOG:
    artists.append((artist_id[name], name, bio, True))
    for alb in albs:
        title, typ, rel, label, trks = alb[:5]
        alb_genres = alb[5] if len(alb) > 5 else genres
        if rel is None:    # release date unknown -> a random one
            rel = dt.date(2018, 1, 1) + dt.timedelta(days=R.randrange((dt.date(2024, 12, 31) - dt.date(2018, 1, 1)).days))
        elif len(rel) == 4:    # only the year is known -> a random day in that year
            rel = dt.date(int(rel), 1, 1) + dt.timedelta(days=R.randrange(365))
        else:
            rel = dt.date.fromisoformat(rel)
        aid = len(albums) + 1
        albums.append((aid, artist_id[name], title, typ, rel, label,
                       f'https://cdn.spotify-demo.example/covers/{aid}.jpg', True))
        for n, t in enumerate(trks, 1):
            tid = len(tracks) + 1
            dur = t['dur'] or R.randint(165, 285)
            tracks.append((tid, aid, t['title'], n, dur, t['explicit'],
                           f'https://cdn.spotify-demo.example/audio/{tid}.mp3'))
            track_artists.append((tid, artist_id[name], True))
            for f in t['feat']:
                track_artists.append((tid, artist_id[f], False))
            for gi, g in enumerate(alb_genres):
                track_genres.append((tid, genre_id[g], gi == 0))
            # hits (tracks with a known length) and singles are played more
            weight = pop * R.lognormvariate(0, 0.55) * (1.9 if t['dur'] else 1.0)
            track_info.append({'id': tid, 'artist': name, 'home': home, 'dur': dur, 'explicit': t['explicit'],
                               'w': weight, 'artists': [name] + t['feat']})

# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
BG_M = ['Ivan', 'Georgi', 'Dimitar', 'Nikolay', 'Petar', 'Stefan', 'Martin', 'Aleksandar', 'Kaloyan', 'Viktor',
        'Boris', 'Hristo', 'Todor', 'Daniel', 'Kristiyan', 'Plamen', 'Yordan', 'Simeon', 'Vasil', 'Angel']
BG_F = ['Maria', 'Elena', 'Ivana', 'Desislava', 'Viktoria', 'Gergana', 'Nikol', 'Aleksandra', 'Yoana', 'Raya',
        'Teodora', 'Kristina', 'Mihaela', 'Petya', 'Silvia', 'Daniela', 'Tsvetelina', 'Gabriela', 'Borislava', 'Kalina']
BG_L = ['Ivanov', 'Georgiev', 'Dimitrov', 'Petrov', 'Nikolov', 'Stoyanov', 'Todorov', 'Hristov', 'Angelov', 'Kolev',
        'Iliev', 'Marinov', 'Popov', 'Vasilev', 'Atanasov', 'Mihaylov', 'Kostov', 'Yordanov', 'Kirilov', 'Aleksandrov']
INT_M = ['James', 'Liam', 'Noah', 'Lucas', 'Oliver', 'Leo', 'Mateo', 'Hugo', 'Luca', 'Jonas', 'Emil', 'Felix',
         'Adam', 'Max', 'Ethan', 'Diego', 'Carlos', 'Kenji', 'Minjun', 'Andrei']
INT_F = ['Emma', 'Olivia', 'Sofia', 'Mia', 'Anna', 'Laura', 'Julia', 'Sara', 'Chloe', 'Lena', 'Nora', 'Clara',
         'Eva', 'Alice', 'Lucia', 'Camila', 'Yuki', 'Jiwoo', 'Hana', 'Ioana']
INT_L = ['Smith', 'Muller', 'Dubois', 'Garcia', 'Rossi', 'Jansen', 'Andersson', 'Johnson', 'Silva', 'Hernandez',
         'Kim', 'Tanaka', 'Papadopoulos', 'Popescu', 'Yilmaz', 'Brown', 'Schmidt', 'Martin', 'Lopez', 'Bianchi',
         'Larsson', 'Williams', 'Santos', 'Park', 'Sato', 'Ionescu', 'Demir', 'Taylor', 'Weber', 'Costa']

iso_index = {c[1]: i + 1 for i, c in enumerate(COUNTRIES)}
users = []
used_names = set()
reg_span = (dt.date(2026, 10, 15) - dt.date(2024, 10, 1)).days
for uid in range(1, N_USERS + 1):
    country = weighted(COUNTRIES, [c[3] for c in COUNTRIES])
    iso = country[1]
    gender = weighted(['Male', 'Female', 'Other'], [49, 49, 2])
    male = gender == 'Male' or (gender == 'Other' and R.random() < 0.5)
    if iso == 'BG':
        first = R.choice(BG_M if male else BG_F)
        last = R.choice(BG_L) + ('' if male else 'a')
    else:
        first, last = R.choice(INT_M if male else INT_F), R.choice(INT_L)
    base = f'{first}.{last}'.lower()
    username, n = base, 1
    while username in used_names:
        n += 1
        username = f'{base}{n}'
    used_names.add(username)
    # registrations grow over time: later dates are more likely
    reg = dt.date(2024, 10, 1) + dt.timedelta(days=int(reg_span * math.sqrt(R.random())))
    age = min(62, max(13, int(R.lognormvariate(math.log(26), 0.32))))
    dob = dt.date(reg.year - age, 1, 1) + dt.timedelta(days=R.randrange(365))
    while age_on(dob, reg) < 13:
        dob -= dt.timedelta(days=200)
    student = 18 <= age_on(dob, reg) <= 26 and R.random() < 0.5
    role = 'Admin' if uid <= 3 else ('Artist' if R.random() < 0.02 else 'Listener')
    users.append({
        'id': uid, 'username': username, 'email': f'{username}@example.com',
        'hash': '%064x' % R.getrandbits(256), 'display': f'{first} {last}', 'dob': dob, 'gender': gender,
        'country': iso_index[iso], 'iso': iso, 'role': role, 'student': student, 'reg': reg,
        'method': weighted(['Card', 'PayPal', 'Voucher'], [65, 28, 7]),
    })

# ---------------------------------------------------------------------------
# Subscriptions and payments  (every user starts on Free)
# ---------------------------------------------------------------------------
subs, pays = [], []      # subs: dicts ; pays: (sub dict, amount, method, status, paid at)


def pick_plan(u, exclude=None):
    names = ['Premium Individual', 'Premium Duo', 'Premium Family']
    weights = [62, 16, 22]
    if u['student']:
        names.append('Premium Student')
        weights.append(190)
    choice = weighted(names, weights)
    while choice == exclude:
        choice = weighted(names, weights)
    return choice


for u in users:
    timeline = []
    state, start = 'Free', u['reg']
    upgrade_at = start + dt.timedelta(days=R.randint(1, 150)) if R.random() < 0.62 else None
    while True:
        if state == 'Free':
            if upgrade_at is None or upgrade_at > END:
                timeline.append({'start': start, 'end': None, 'plan': 'Free', 'status': 'Active', 'renew': False})
                break
            timeline.append({'start': start, 'end': upgrade_at, 'plan': 'Free', 'status': 'Expired', 'renew': False})
            state, start = pick_plan(u), upgrade_at
            continue
        sub = {'start': start, 'end': None, 'plan': state, 'status': 'Active', 'renew': True}
        timeline.append(sub)
        bill, first, outcome = start, True, None
        while bill <= END:
            if not first:
                r = R.random()
                if r < 0.035:
                    outcome = 'cancel'
                elif r < 0.057:
                    outcome = 'failed'
                    pays.append((sub, PRICE[state], u['method'], 'Failed', rand_dt(bill)))
                elif r < 0.067:
                    outcome = 'switch'
                if outcome:
                    break
            first = False
            status = 'Refunded' if R.random() < 0.008 else 'Successful'
            pays.append((sub, PRICE[state], u['method'], status, rand_dt(bill)))
            bill = add_month(bill)
        if outcome is None:
            sub['renew'] = R.random() > 0.06        # a few users already cancelled the renewal
            break
        sub['end'] = bill
        sub['status'] = 'Cancelled' if outcome == 'cancel' else 'Expired'
        sub['renew'] = outcome != 'cancel'
        start = bill
        if outcome == 'switch':
            state = pick_plan(u, exclude=state)
        else:
            state = 'Free'
            upgrade_at = start + dt.timedelta(days=R.randint(30, 200)) if R.random() < 0.35 else None
    u['timeline'] = timeline
    for s in timeline:
        s['user'] = u['id']
        subs.append(s)

subs.sort(key=lambda s: (s['start'], s['user']))
for i, s in enumerate(subs, 1):
    s['id'] = i
pays.sort(key=lambda p: p[4])
plan_id = {p[0]: i + 1 for i, p in enumerate(PLANS)}


def premium_on(u, day):
    for s in u['timeline']:
        if s['start'] <= day and (s['end'] is None or s['end'] > day):
            return s['plan'] != 'Free'
    return False


# ---------------------------------------------------------------------------
# Streams
# ---------------------------------------------------------------------------
def affinity(u, t):
    home = t['home']
    if home == 'BG':
        return 7.0 if u['iso'] == 'BG' else 0.25
    if home == 'KR':
        return 4.0 if u['iso'] in ('KR', 'JP') else 1.0
    if home == 'LATAM':
        return 3.5 if u['iso'] in ('ES', 'MX', 'BR') else 1.0
    return 1.0


device_ids = list(range(1, len(DEVICES) + 1))
device_w = [d[2] for d in DEVICES]
artist_names = [a[0] for a in CATALOG if a[5]]
artist_pop = {a[0]: a[3] for a in CATALOG}
artist_home = {a[0]: a[4] for a in CATALOG}

rates = []
for u in users:
    first_day = max(u['reg'], START)
    u['days'] = (END - first_day).days + 1
    u['first_day'] = first_day
    prem_days = sum(((s['end'] or END) - max(s['start'], first_day)).days
                    for s in u['timeline'] if s['plan'] != 'Free' and (s['end'] or END) > first_day)
    u['rate'] = R.lognormvariate(0, 0.85) * u['days'] * (1 + 1.2 * prem_days / max(1, u['days']))
    rates.append(u['rate'])
    favs = set()
    w = [artist_pop[a] * affinity(u, {'home': artist_home[a]}) for a in artist_names]
    while len(favs) < R.randint(2, 4):
        favs.add(weighted(artist_names, w))
    u['favs'] = favs
    u['dev1'] = weighted(device_ids, device_w)
    u['dev2'] = weighted(device_ids, device_w)

scale = N_STREAMS / sum(rates)
streams = []
for u in users:
    n = max(3, int(round(u['rate'] * scale)))
    weights_adult, weights_minor = [], []
    for t in track_info:
        w = t['w'] * affinity(u, t) * (8.0 if t['artist'] in u['favs'] else 1.0)
        weights_adult.append(w)
        weights_minor.append(0.0 if t['explicit'] else w)
    cum_adult = [sum(weights_adult[:i + 1]) for i in range(len(weights_adult))]
    cum_minor = [sum(weights_minor[:i + 1]) for i in range(len(weights_minor))]
    for _ in range(n):
        while True:    # weekends are a bit busier
            day = u['first_day'] + dt.timedelta(days=R.randrange(u['days']))
            if day.weekday() >= 5 or R.random() < 0.8:
                break
        when = rand_dt(day)
        cum = cum_minor if age_on(u['dob'], day) < 18 else cum_adult
        t = track_info[bisect.bisect_left(cum, R.random() * cum[-1])]
        premium = premium_on(u, day)
        skipped = R.random() < (0.12 if premium else 0.24)
        if skipped:
            seconds = R.randint(2, min(45, t['dur'] - 1))
        elif R.random() < 0.85:
            seconds = t['dur']
        else:
            seconds = R.randint(int(t['dur'] * 0.6), t['dur'])
        dev = u['dev1'] if R.random() < 0.72 else (u['dev2'] if R.random() < 0.7 else R.choice(device_ids))
        country = u['country'] if R.random() < 0.96 else R.randint(1, len(COUNTRIES))
        streams.append({'user': u['id'], 'track': t, 'country': country, 'device': dev, 'at': when,
                        'sec': seconds, 'skip': skipped, 'premium': premium})

streams.sort(key=lambda s: (s['at'], s['user']))

# Free plan: at most 6 skips per hour
by_user = {}
for s in streams:
    by_user.setdefault(s['user'], []).append(s)
for lst in by_user.values():
    recent = []
    for s in lst:
        if s['skip'] and not s['premium']:
            recent = [x for x in recent if (s['at'] - x).total_seconds() < 3600]
            if len(recent) >= 6:
                s['skip'], s['sec'] = False, s['track']['dur']
            else:
                recent.append(s['at'])

# ---------------------------------------------------------------------------
# Likes, follows, playlists
# ---------------------------------------------------------------------------
liked, artist_follows, user_follows, playlists, playlist_tracks = [], [], [], [], []
PLAYLIST_NAMES = ['Workout Mix', 'Chill Vibes', 'Road Trip', 'Study Session', 'Party Hits', 'Morning Coffee',
                  'Throwback', 'Late Night', 'Focus', 'Gym', 'Summer 2026', 'Favorites', 'K-Pop Bops', 'Balkan Hits',
                  'Rainy Day', 'Sunday Mood', 'Driving', 'Feel Good', 'Top Tracks', 'Discover']
users_by_id = {u['id']: u for u in users}

for u in users:
    mine = by_user.get(u['id'], [])
    first_play, plays_per_artist = {}, {}
    for s in mine:
        if not s['skip'] and s['sec'] >= 30:
            first_play.setdefault(s['track']['id'], s)
            for a in s['track']['artists']:
                plays_per_artist.setdefault(a, []).append(s['at'])
    # liked songs
    ids = list(first_play)
    R.shuffle(ids)
    for tid in ids[:min(len(ids), int(R.lognormvariate(1.9, 0.9)))]:
        s = first_play[tid]
        liked.append((u['id'], tid, s['at'] + dt.timedelta(seconds=s['sec'])))
    # followed artists: the ones the user plays most
    top = sorted(plays_per_artist, key=lambda a: -len(plays_per_artist[a]))[:R.randint(0, 7)]
    for a in top:
        artist_follows.append((u['id'], artist_id[a], min(plays_per_artist[a]) + dt.timedelta(minutes=R.randint(3, 600))))
    # followed users
    for _ in range(R.randint(0, 3)):
        same = [x for x in users if x['iso'] == u['iso'] and x['id'] != u['id']]
        other = R.choice(same) if same and R.random() < 0.6 else R.choice(users)
        if other['id'] == u['id']:
            continue
        day0 = max(u['reg'], other['reg'], START)
        when = rand_dt(day0 + dt.timedelta(days=R.randrange((END - day0).days + 1)))
        user_follows.append((u['id'], other['id'], when))
    # playlists
    if ids and R.random() < 0.6:
        for _ in range(R.randint(1, 3)):
            created = rand_dt(u['first_day'] + dt.timedelta(days=R.randrange(u['days'])))
            pid = len(playlists) + 1
            pool = list(dict.fromkeys(ids + [t['id'] for t in R.sample(track_info, 15)]))
            R.shuffle(pool)
            chosen = pool[:R.randint(5, min(25, len(pool)))]
            last = created
            for pos, tid in enumerate(chosen, 1):
                last = min(dt.datetime(END.year, END.month, END.day, 23, 59, 59),
                           last + dt.timedelta(minutes=R.randint(1, 60 * 24 * 12)))
                playlist_tracks.append((pid, tid, pos, last))
            playlists.append((pid, u['id'], R.choice(PLAYLIST_NAMES), None, R.random() < 0.7, created, last))

user_follows = list({(a, b): (a, b, w) for a, b, w in user_follows}.values())

# ---------------------------------------------------------------------------
# Write the SQL file
# ---------------------------------------------------------------------------
header = f"""/* ============================================================================
   Spotify - music streaming platform            (course work, FN 2401321010)
   03_seed_data.sql : fills SpotifyDB with sample data.

   GENERATED FILE - do not edit by hand. It is produced by tools/gen_seed_data.py
   Run it once, on an empty database, after 01_create_database.sql and
   02_programmability.sql. Listening data covers {START} .. {END}.

   The triggers stay enabled while loading, so Tracks.PlayCount and
   Artists.FollowersCount are filled by them. Only trg_Users_AssignFreePlan is
   switched off, because the subscription history is loaded explicitly.
   ============================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO
USE SpotifyDB;
GO
IF EXISTS (SELECT 1 FROM dbo.Users)
BEGIN
    RAISERROR('SpotifyDB already contains data. Run 01_create_database.sql first.', 16, 1);
    SET NOEXEC ON;
END
GO"""
out.append(header)

emit('Countries', ['CountryID', 'Name', 'IsoCode', 'Region'],
     [(i + 1, c[0], c[1], c[2]) for i, c in enumerate(COUNTRIES)], True)
emit('Devices', ['DeviceID', 'DeviceType', 'Platform'],
     [(i + 1, d[0], d[1]) for i, d in enumerate(DEVICES)], True)
emit('Genres', ['GenreID', 'Name', 'Description'], [(i + 1, g[0], g[1]) for i, g in enumerate(GENRES)], True)
emit('SubscriptionPlans', ['PlanID', 'Name', 'MonthlyPrice', 'MaxAccounts', 'HasAds', 'AllowsOffline', 'SkipsPerHour'],
     [(i + 1, p[0], float(p[1]), p[2], bool(p[3]), bool(p[4]), p[5]) for i, p in enumerate(PLANS)], True)
emit('Artists', ['ArtistID', 'Name', 'Bio', 'IsVerified'], artists, True)
emit('Albums', ['AlbumID', 'ArtistID', 'Title', 'AlbumType', 'ReleaseDate', 'Label', 'CoverImageUrl', 'IsApproved'],
     albums, True)
emit('Tracks', ['TrackID', 'AlbumID', 'Title', 'TrackNumber', 'DurationSeconds', 'IsExplicit', 'AudioUrl'],
     tracks, True)
emit('TrackArtists', ['TrackID', 'ArtistID', 'IsMainArtist'], track_artists)
emit('TrackGenres', ['TrackID', 'GenreID', 'IsPrimary'], track_genres)

out.append('DISABLE TRIGGER dbo.trg_Users_AssignFreePlan ON dbo.Users;\nGO')
emit('Users', ['UserID', 'Username', 'Email', 'PasswordHash', 'DisplayName', 'DateOfBirth', 'Gender', 'CountryID',
               'Role', 'IsStudentVerified', 'RegistrationDate'],
     [(u['id'], u['username'], u['email'], u['hash'], u['display'], u['dob'], u['gender'], u['country'], u['role'],
       u['student'], u['reg']) for u in users], True)
out.append('ENABLE TRIGGER dbo.trg_Users_AssignFreePlan ON dbo.Users;\nGO')

emit('Subscriptions', ['SubscriptionID', 'UserID', 'PlanID', 'StartDate', 'EndDate', 'Status', 'AutoRenew'],
     [(s['id'], s['user'], plan_id[s['plan']], s['start'], s['end'], s['status'], s['renew']) for s in subs], True)
emit('Payments', ['PaymentID', 'SubscriptionID', 'Amount', 'Currency', 'PaymentMethod', 'Status', 'PaidAt'],
     [(i, p[0]['id'], float(p[1]), 'EUR', p[2], p[3], p[4]) for i, p in enumerate(pays, 1)], True)
emit('Streams', ['StreamID', 'UserID', 'TrackID', 'CountryID', 'DeviceID', 'StartedAt', 'SecondsPlayed', 'IsSkipped'],
     [(i, s['user'], s['track']['id'], s['country'], s['device'], s['at'], s['sec'], s['skip'])
      for i, s in enumerate(streams, 1)], True)
emit('LikedTracks', ['UserID', 'TrackID', 'LikedAt'], liked)
emit('ArtistFollowers', ['UserID', 'ArtistID', 'FollowedAt'], artist_follows)
emit('UserFollowers', ['FollowerID', 'FollowedUserID', 'FollowedAt'], user_follows)
emit('Playlists', ['PlaylistID', 'UserID', 'Name', 'Description', 'IsPublic', 'CreatedAt', 'UpdatedAt'],
     playlists, True)
emit('PlaylistTracks', ['PlaylistID', 'TrackID', 'Position', 'AddedAt'], playlist_tracks)

out.append(f"""-- derived statistics: listeners in the last 30 days of the data
EXEC dbo.usp_RefreshArtistStats @AsOf = '{END}';
GO
SET NOEXEC OFF;
GO
PRINT 'SpotifyDB seed data loaded.';
GO""")

with open(OUT, 'w', encoding='utf-8-sig', newline='\n') as f:
    f.write('\n'.join(out) + '\n')

print(f'artists {len(artists)}, albums {len(albums)}, tracks {len(tracks)}, users {len(users)}, '
      f'subscriptions {len(subs)}, payments {len(pays)}, streams {len(streams)}, likes {len(liked)}, '
      f'artist follows {len(artist_follows)}, user follows {len(user_follows)}, playlists {len(playlists)}, '
      f'playlist tracks {len(playlist_tracks)}')
print(f'written {os.path.getsize(OUT) / 1024:.0f} KB -> database/03_seed_data.sql')
