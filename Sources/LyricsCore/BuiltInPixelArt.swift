import Foundation

/// The sprites that ship with the app. Each frame is a grid of palette keys, at most 16 × 16; `.` is transparent.
public enum BuiltInPixelArt {
    /// The retro palette the built-in sprites are drawn with, in the order the editor offers it.
    public static let palette: [(key: Character, color: UInt32)] = [
        ("R", 0xFF4D6DFF),
        ("r", 0xB3123FFF),
        ("P", 0xFF8FABFF),
        ("p", 0xFFC2D1FF),
        ("O", 0xFF8A1FFF),
        ("o", 0xD9480FFF),
        ("Y", 0xFFD23FFF),
        ("y", 0xE0A100FF),
        ("l", 0xFFF6C2FF),
        ("t", 0xF2C29BFF),
        ("N", 0xB86B3CFF),
        ("n", 0x7A4424FF),
        ("L", 0xB6F09CFF),
        ("G", 0x4CC26BFF),
        ("v", 0x1F7A44FF),
        ("c", 0xBFEFFFFF),
        ("C", 0x38C6F4FF),
        ("B", 0x3D8BFFFF),
        ("b", 0x1F4FBFFF),
        ("m", 0xD4A5FFFF),
        ("V", 0x9B5DE5FF),
        ("u", 0x5A2CA0FF),
        ("W", 0xFFFFFFFF),
        ("g", 0xC9CED6FF),
        ("a", 0x8A919CFF),
        ("k", 0x4A4F57FF),
        ("K", 0x1C1E22FF),
    ]

    /// Brightness of each palette color in the white style. Tuned by hand so details such as windows stay visible.
    static let whiteLevels: [UInt32: Double] = [
        0xFF4D6DFF: 0.9,
        0xB3123FFF: 0.45,
        0xFF8FABFF: 0.95,
        0xFFC2D1FF: 1,
        0xFF8A1FFF: 0.8,
        0xD9480FFF: 0.45,
        0xFFD23FFF: 0.95,
        0xE0A100FF: 0.5,
        0xFFF6C2FF: 1,
        0xF2C29BFF: 0.85,
        0xB86B3CFF: 0.7,
        0x7A4424FF: 0.4,
        0xB6F09CFF: 1,
        0x4CC26BFF: 0.7,
        0x1F7A44FF: 0.4,
        0xBFEFFFFF: 0.3,
        0x38C6F4FF: 0.75,
        0x3D8BFFFF: 0.9,
        0x1F4FBFFF: 0.45,
        0xD4A5FFFF: 1,
        0x9B5DE5FF: 0.85,
        0x5A2CA0FF: 0.4,
        0xFFFFFFFF: 1,
        0xC9CED6FF: 0.65,
        0x8A919CFF: 0.55,
        0x4A4F57FF: 0.5,
        0x1C1E22FF: 0.15,
    ]

    /// Phrases that contain a trigger word but mean something else, like 小心 ("careful") around 心 ("heart").
    public static let ignoredPhrases = [
        "小心", "中心", "點心", "擔心", "耐心", "粗心", "當心", "噁心", "心理", "信心", "星期", "明星", "上海", "大家", "國家", "專家", "作家",
    ]

    public static let sprites: [PixelSprite] = [
        // MARK: Love and feelings

        sprite("heart", "Heart", .beat, "love, loved, loving, lover, heart, sweetheart, 愛, 愛情, 心, 喜歡, 親愛, 愛心, 真心, 心動", [
            """
            ..rrr...rrr..
            .rRRRr.rRRRr.
            rRppRRrRRRRRr
            rRpRRRRRRRRRr
            rRRRRRRRRRRRr
            rRRRRRRRRRRRr
            .rRRRRRRRRRr.
            ..rRRRRRRRr..
            ...rRRRRRr...
            ....rRRRr....
            .....rRr.....
            ......r......
            """,
        ]),

        sprite("broken_heart", "Broken heart", .stay, "heartbreak, heartbreaker, heartbroken, heartache, broken heart, break my heart, broke my heart, breaking my heart, 心碎, 傷心, 分手, 失戀", [
            """
            ..rrr...rrr..
            .rRRRr.rRRRr.
            rRppRr.rRRRRr
            rRpRRRr.rRRRr
            rRRRRr.rRRRRr
            rRRRRRr.rRRRr
            .rRRRr.rRRRr.
            ..rRRRr.rRr..
            ...rRr.rRr...
            ....rRr.r....
            .....r.r.....
            """,
        ]),

        sprite("kiss", "Kiss", .beat, "kiss, kissed, kissing, lips, 吻, 親吻, 親親", [
            """
            ...rr...rr...
            ..rRRr.rRRr..
            .rRPRRrRRRRr.
            rRPRRRRRRRRRr
            rrrrrrrrrrrrr
            .rRRRRRRRRRr.
            ..rRRRRRRRr..
            ....rrrrr....
            """,
        ]),

        sprite("tear", "Tear", .fall, "tears, teardrop, cry, cried, crying, weep, weeping, 眼淚, 淚, 哭, 哭泣, 流淚", [
            """
            ...bb...
            ...bb...
            ..bCCb..
            ..bCCb..
            .bCCCCb.
            .bCcCCb.
            bCccCCCb
            bCcCCCCb
            bCCCCCCb
            bCCCCCCb
            .bCCCCb.
            ..bbbb..
            """,
        ]),

        sprite("smile", "Smile", .bounce, "smile, smiled, smiling, smiley, happy, happiness, laugh, laughed, laughing, 笑, 微笑, 笑容, 快樂, 開心, 歡笑", [
            """
            ...yyyyyy...
            .yyYYYYYYyy.
            .yYlYYYYYYy.
            yYlYYYYYYYYy
            yYYYKYYKYYYy
            yYYYKYYKYYYy
            yYYYYYYYYYYy
            yYKYYYYYYKYy
            yYYKYYYYKYYy
            .yYYKKKKYYy.
            .yyYYYYYYyy.
            ...yyyyyy...
            """,
        ]),

        sprite("fire", "Fire", .stay, fps: 6, "fire, flame, flames, burn, burned, burning, burnt, blaze, 火, 火焰, 燃燒", [
            """
            ....o.....
            ....oo....
            ...oOo..o.
            ..oOOo.oo.
            ..oOYOooO.
            .oOYYYOOo.
            .oOYYYYOOo
            oOYYWYYYOo
            oOYWWWYYOo
            oOYWWWWYOo
            .oOYWWYYo.
            ..ooYYoo..
            ....oo....
            """,
            """
            .....o....
            ....oo....
            .o..oOo...
            .oo.oOOo..
            .OooOYOo..
            .oOOYYYOo.
            oOOYYYYOo.
            oOYYYWYYOo
            oOYYWWWYOo
            oOYWWWWYOo
            .oYYWWYOo.
            ..ooYYoo..
            ....oo....
            """,
        ]),

        // MARK: Vehicles

        sprite("car", "Car", .drive, "car, drive, drove, driving, driven, 車, 汽車, 開車, 跑車", [
            """
            .....bbbbbb.....
            ....bccbcccb....
            ...bcccbccccb...
            .bbBBBBBBBBBBbb.
            bBBBBBBBBBBBBBBY
            RBBBBBBBBBBBBBBB
            bBBBBBBBBBBBBBBb
            .bbkkkbbbbbkkkb.
            ...kgk.....kgk..
            ...kkk.....kkk..
            """,
        ]),

        sprite("bus", "Bus", .drive, "bus, school bus, 公車, 巴士, 公交, 公交車", [
            """
            .yyyyyyyyyyyyyy.
            yYYYYYYYYYYYYYYy
            yYccYccYccYcccYy
            yYccYccYccYcccYy
            yYYYYYYYYYYYYYYy
            yOOOOOOOOOOOOOOy
            yYYYYYYYYYYYYYYW
            yYYYYYYYYYYYYYYy
            .yykkkyyyyykkkyy
            ...kgk.....kgk..
            ...kkk.....kkk..
            """,
        ]),

        sprite("plane", "Plane", .fly, "plane, airplane, aeroplane, jet, flight, airport, 飛機, 班機, 機場", [
            """
            .gg.............
            .gWg............
            .gWWg...........
            .gWWWgggggggggg.
            gWWWWWWWWWWWbbWg
            gWbWbWbWbWbWWWWW
            .gWWWWWWWWWWWWg.
            ..gggggWWWWggg..
            .......gWWWg....
            ........gWWWg...
            .........gggg...
            """,
        ]),

        sprite("train", "Train", .drive, "train, subway, metro, railway, railroad, 火車, 地鐵, 捷運, 列車, 高鐵", [
            """
            .aaaaaaaaaaa....
            agggggggggggaa..
            agccgccgccggcca.
            agccgccgccgggcca
            agggggggggggggga
            aBBBBBBBBBBBBBBa
            agggggggggggggga
            .aaaaaaaaaaaaaa.
            ...kk...kk...kk.
            kkkkkkkkkkkkkkkk
            """,
        ]),

        sprite("bike", "Bike", .drive, "bike, bicycle, 腳踏車, 單車, 自行車", [
            """
            ...nnn.....aa...
            ....R......R....
            ....RRRRRRRR....
            ...R.R....R.R...
            .kkkk.R..R.kkkk.
            k...Rk.RR.k....k
            k...R.kRRk.....k
            k....RkaakR....k
            k.....kaak.....k
            .k...k....k...k.
            ..kkk......kkk..
            """,
        ]),

        sprite("boat", "Boat", .drive, "boat, ship, sail, sailed, sailing, sailor, 船, 帆船, 航行", [
            """
            ......n.........
            ......nW........
            ......nWW.......
            ......nWWW......
            ...W..nWWWW.....
            ..WW..nWgWWW....
            .WWW..nWggWWW...
            WWgW..nWgggWWW..
            WWWW..nWWWWWWWW.
            ......n.........
            NNNNNNNNNNNNNNNN
            .NNNNNNNNNNNNNN.
            ..nnnnnnnnnnnn..
            """,
        ]),

        sprite("rocket", "Rocket", .fly, "rocket, rockets, spaceship, outer space, 火箭, 太空船, 太空", [
            """
            .....r.....
            ....rRr....
            ...rRRRr...
            ...gWWWg...
            ..gWWWWWg..
            ..gWcccWg..
            ..gWcCcWg..
            ..gWcccWg..
            ..gWWWWWg..
            ..gWWWWWg..
            .rgWWWWWgr.
            rRgWWWWWgRr
            rR.gWWWg.Rr
            r..OYYYO..r
            ....OYO....
            .....O.....
            """,
        ]),

        // MARK: Sky and weather

        sprite("sun", "Sun", .stay, fps: 2, "sun, sunshine, sunny, sunlight, sunrise, 太陽, 陽光, 日出", [
            """
            ......O......
            .O....O....O.
            ..O.......O..
            ....yyyyy....
            ...yYYYYYy...
            ...yYlYYYy...
            OO.yYYYYYy.OO
            ...yYYYYYy...
            ...yYYYYYy...
            ....yyyyy....
            ..O.......O..
            .O....O....O.
            ......O......
            """,
            """
            .............
            ......O......
            .O.........O.
            ....yyyyy....
            ...yYYYYYy...
            ...yYlYYYy...
            .O.yYYYYYy.O.
            ...yYYYYYy...
            ...yYYYYYy...
            ....yyyyy....
            .O.........O.
            ......O......
            .............
            """,
        ]),

        sprite("moon", "Moon", .stay, "moon, moonlight, moonlit, 月亮, 月光, 明月, 月色", [
            """
            ....yyyyy
            ..yyYYyy.
            .yYYYy...
            .yYYy....
            yYYYy....
            yYYYy....
            yYYYy....
            yYYYy....
            .yYYy....
            .yYYYy...
            ..yyYYyy.
            ....yyyyy
            """,
        ]),

        sprite("star", "Star", .twinkle, "star, starlight, starry, shooting star, 星星, 星, 星空, 流星, 星光", [
            """
            ......y......
            .....yYy.....
            .....yYy.....
            ....yYYYy....
            yyyyyYlYyyyyy
            .yYYYYYYYYYy.
            ..yYYYYYYYy..
            ...yYYYYYy...
            ...yYYYYYy...
            ..yYYyyyYYy..
            ..yYy...yYy..
            .yy.......yy.
            """,
        ]),

        sprite("cloud", "Cloud", .stay, "cloud, cloudy, 雲, 雲朵, 白雲", [
            """
            .....gggg.......
            ...ggWWWWg......
            ..gWWWWWWWgggg..
            .gWWWWWWWWWWWWg.
            gWWWWWWWWWWWWWWg
            gWWWWWWWWWWWWWWg
            .gggggggggggggg.
            """,
        ]),

        sprite("rain", "Rain", .stay, fps: 4, "rain, rained, raining, rainy, raindrop, 雨, 下雨, 雨天", [
            """
            .....aaaa.......
            ...aaggggaa.....
            ..aggggggggaaa..
            .aggggggggggggga
            agggggggggggggga
            agggggggggggggga
            .aaaaaaaaaaaaaa.
            ................
            ..B....B....B...
            .B....B....B....
            ................
            ....B....B....B.
            ...B....B....B..
            """,
            """
            .....aaaa.......
            ...aaggggaa.....
            ..aggggggggaaa..
            .aggggggggggggga
            agggggggggggggga
            agggggggggggggga
            .aaaaaaaaaaaaaa.
            ....B....B....B.
            ...B....B....B..
            ................
            ..B....B....B...
            .B....B....B....
            ................
            """,
        ]),

        sprite("snow", "Snow", .fall, "snow, snowing, snowflake, winter, 雪, 下雪, 雪花, 冬天", [
            """
            ......W......
            ....W.W.W....
            .....WWW.....
            .W....W....W.
            ..W...W...W..
            ...WW.W.WW...
            WWWWWWcWWWWWW
            ...WW.W.WW...
            ..W...W...W..
            .W....W....W.
            .....WWW.....
            ....W.W.W....
            ......W......
            """,
        ]),

        sprite("lightning", "Lightning", .twinkle, "lightning, thunder, storm, stormy, 閃電, 雷, 打雷, 暴風雨", [
            """
            ....yyyyy
            ...yYYYy.
            ...yYYy..
            ..yYYy...
            .yYYYyyy.
            yYYYYYYy.
            yyyyYYy..
            ...yYy...
            ..yYy....
            ..yYy....
            .yYy.....
            .yy......
            yy.......
            """,
        ]),

        sprite("rainbow", "Rainbow", .stay, "rainbow, 彩虹", [
            """
            ....RRRRRRRR....
            ..RROOOOOOOORR..
            .ROOYYYYYYYYOOR.
            .ROYYGGGGGGYYOR.
            ROYGGBBBBBBGGYOR
            ROYGBBVVVVBBGYOR
            ROYGBV....VBGYOR
            ROYGBV....VBGYOR
            gWWWgV....VgWWWg
            .ggg........ggg.
            """,
        ]),

        // MARK: Nature

        sprite("flower", "Flower", .stay, "flower, bloom, blossom, rose, garden, 花, 玫瑰, 花朵, 開花, 花園", [
            """
            ...rRRr...
            ..rRRrRr..
            .rRRrRRrr.
            .rRrRRRrR.
            .rRRrrrRr.
            ..rRRRRr..
            ...rrrr...
            .....v....
            .GG..v....
            GLGG.v.GG.
            .GGGvvGLGG
            ....v..GG.
            ....v.....
            ....v.....
            """,
        ]),

        sprite("tree", "Tree", .stay, "tree, forest, woods, 樹, 樹林, 森林", [
            """
            ....vvvvv....
            ..vvGGGGGvv..
            .vGGGLGGGGGv.
            vGGLGGGGGGGGv
            vGGGGGGGLGGGv
            vGGGGGGGGGGGv
            .vGGGGLGGGGv.
            vGGGGGGGGGGGv
            vGGLGGGGGGGGv
            .vvGGGGGGGvv.
            ...vvvNvvv...
            .....NNN.....
            .....NnN.....
            .....NnN.....
            ....nNNNn....
            """,
        ]),

        sprite("wave", "Ocean", .stay, fps: 2.5, "ocean, sea, wave, beach, tide, 海, 大海, 海浪, 浪, 海邊, 海灘", [
            """
            .....bbbbb......
            ...bbCCCCCbb....
            ..bCCccccCCCb...
            .bCCc....WcCCb..
            .bCc.....WWcCb..
            bCCc......W.bb..
            bCCcW...........
            bBCCcWW.......W.
            bBBCCccWWW..WWc.
            bBBBCCCccccCCcCb
            bbbbbbbbbbbbbbbb
            """,
            """
            .....bbbbb......
            ...bbCCCCCbb....
            ..bCCccccCCCb...
            .bCCc....WcCCb..
            .bCc......WcCb..
            bCCc.......Wbb..
            bCCc............
            bBCCcW..........
            bBBCCcWW.....WW.
            bBBBCCCcccWWCcCb
            bbbbbbbbbbbbbbbb
            """,
        ]),

        sprite("mountain", "Mountain", .stay, "mountain, hill, hills, peak, 山, 高山, 山頂", [
            """
            ......W.........
            .....WWW........
            ....WWgWW.......
            ....aWgga...W...
            ...aaagaaa.WWW..
            ..aaakaaaaWWgWW.
            ..akaaakaaaWgaa.
            .aaaakaaakaagaaa
            .akaaaaakaaaakaa
            aaakaaakaaaaaaka
            kkkkkkkkkkkkkkkk
            """,
        ]),

        sprite("earth", "Earth", .stay, fps: 2.5, "world, earth, planet, globe, 世界, 地球, 全世界", [
            """
            ....vvbbb....
            ..bvGGGBBbb..
            .bGGGGGGBBBb.
            .vGGGGBBBBBv.
            bGGGBBBBBBGGv
            bBGGBBBBBBGGv
            bBBGBBBBBBBGv
            bBBBBBBBBBBGv
            bBBBBGGBBBBBv
            .bBBGGGGBBBb.
            .bBBBGGGGBBb.
            ..bbBBGGBbb..
            ....bbbbb....
            """,
            """
            ....bbbbb....
            ..vbBBBBBbb..
            .vGGBBBBBBBb.
            .vBBBBBGBBBb.
            bBBBBBGGGBBBb
            bBBBBBGGGGBBb
            bBBBBBBGGGGGb
            bBBBBBBGGGGBb
            bGGBBBBBGGBBb
            .vGGBBBBBGBb.
            .vGGGBBBBBBb.
            ..vvBBBBBbb..
            ....bbbbb....
            """,
            """
            ....bbbbv....
            ..bbBBBGGvv..
            .bBBBBBBGGGb.
            .bBGBBBBBGBb.
            bBGGGBBBBBBBv
            bBGGGGBBBBBBb
            bBBGGGGGBBBBb
            bBBGGGGBBBBBb
            bBBBGGBBBBBBv
            .bBBBGBBBBBv.
            .bBBBBBBBBBb.
            ..bbBBBBBbb..
            ....bbbbb....
            """,
            """
            ....vvbbb....
            ..bvGGGBBbb..
            .bBBGGGBBBGv.
            .bBBBGBBBGGv.
            vBBBBBBBGGGGv
            vGBBBBBBBGGGv
            vGGGBBBBBBGGb
            vGGBBBBBBBBBb
            vGBBBBBBGBBBb
            .vBBBBBGGGBb.
            .bBBBBBBGGBb.
            ..bbBBBBBbb..
            ....bbbbb....
            """,
        ]),

        // MARK: Music and nights out

        sprite("music", "Music", .float, "music, song, sing, sang, sung, singing, melody, 音樂, 歌, 唱歌, 旋律, 歌曲", [
            """
            ....uVVVVVV
            ....VVVVVVV
            ....V.....V
            ....V.....V
            ....V.....V
            ....V.....V
            ..VVV...VVV
            .VmVV..VmVV
            VVVVV.VVVVV
            VVVV..VVVV.
            .VV....VV..
            """,
        ]),

        sprite("guitar", "Guitar", .bounce, "guitar, guitars, 吉他", [
            """
            ............kk
            ...........okk
            ..........oNok
            .........oNo..
            .....ooooOo...
            ...ooOOOOo....
            .ooOOOOOOo....
            .oOlOnnOOo....
            oOlOOnnOOo....
            oOOOOOOOo.....
            oOnnOOOOo.....
            .oOnnOOo......
            .ooOOOoo......
            ...ooo........
            """,
        ]),

        sprite("microphone", "Microphone", .stay, "microphone, mic, karaoke, 麥克風, 卡拉OK", [
            """
            ..aaaa..
            .agWgga.
            agWgagga
            agagagga
            aggagaga
            .agagaa.
            ..aaaa..
            ..gggg..
            ..gWga..
            ...ga...
            ...ga...
            ...ga...
            ...ga...
            ...aa...
            """,
        ]),

        sprite("disco", "Disco ball", .twinkle, fps: 3, "dance, danced, dancing, dancer, party, disco, dance floor, 跳舞, 舞, 派對, 舞池", [
            """
            .....aa.....
            .....aa.....
            ....kagk....
            ..kkaaggkk..
            .kacggaaggk.
            .kcWcgaaggk.
            kagcaaggaagk
            kaggaaggaagk
            kgaaggaacgak
            kgaaggacWcak
            .kggaaggcak.
            .kggaacgaak.
            ..kkgcWckk..
            ....kkck....
            """,
            """
            .....aa.....
            .....aa.....
            ....kagk....
            ..kkaaggkk..
            .kaaggaaggk.
            .kaaggacggk.
            kaggaacWcagk
            kaggaagcaagk
            kgaaggaaggak
            kgacggaaggak
            .kcWcaggaak.
            .kgcaaggack.
            ..kkggaacW..
            ....kkkk....
            """,
        ]),

        sprite("city", "City", .stay, fps: 1.5, "city, town, downtown, skyline, 城市, 都市, 城", [
            """
            ..........V.....
            ..........V.....
            .........VVV....
            ...VVV...VuV....
            ...VuV...VVV.VVV
            ...VYV...VYV.VuV
            VVVVuV.VVVuV.VYV
            VuVVYV.VYVuV.VuV
            VYVVuV.VuVYV.VYV
            VuVVYVVVYVuVVVuV
            VYVVuVVVuVYVVVYV
            VuVVYVVVYVuVVVuV
            VVVVVVVVVVVVVVVV
            """,
            """
            ..........V.....
            ..........V.....
            .........VVV....
            ...VVV...VuV....
            ...VuV...VVV.VVV
            ...VuV...VuV.VYV
            VVVVYV.VVVYV.VuV
            VYVVuV.VuVuV.VYV
            VuVVYV.VYVYV.VuV
            VYVVuVVVuVuVVVYV
            VuVVYVVVYVYVVVuV
            VYVVuVVVuVuVVVYV
            VVVVVVVVVVVVVVVV
            """,
        ]),

        // MARK: Things

        sprite("home", "Home", .stay, "home, house, 家, 回家, 房子, 家人", [
            """
            .........kk...
            ......rr.kk...
            .....rRRrkk...
            ....rRRRRrk...
            ...rRRRRRRr...
            ..rRRRRRRRRr..
            .rRRRRRRRRRRr.
            rrrrrrrrrrrrrr
            .tttttttttttt.
            .tccctttNNNtt.
            .tcYctttNNNtt.
            .tccctttNNYtt.
            .tttttttNNNtt.
            nnnnnnnnnnnnnn
            """,
        ]),

        sprite("clock", "Clock", .stay, "clock, o'clock, alarm, tick tock, 時鐘, 鬧鐘, 點鐘", [
            """
            ....aaaaa....
            ..aaWWkWWaa..
            .aWWWWkWWWWa.
            .aWWWWkWWWWa.
            aWWWWWkWkkWWa
            aWWWWWkkkWWWa
            akWWWWRWWWWka
            aWWWWWWWWWWWa
            aWWWWWWWWWWWa
            .aWWWWWWWWWa.
            .aWWWWWWWWWa.
            ..aaWWkWWaa..
            ....aaaaa....
            """,
        ]),

        sprite("phone", "Phone", .bounce, "phone, telephone, cellphone, call me, call you, calling me, calling you, text me, 電話, 手機, 打電話", [
            """
            .ggggggg.
            gaaakaaag
            gCCCCCCCg
            gCcCCCCCg
            gCccCCCCg
            gCCcCCCCg
            gCCCCCCCg
            gCCCCCCCg
            gCCCCCCCg
            gCCCCCCCg
            gCCCCCCCg
            gaaaaaaag
            gaaagaaag
            .ggggggg.
            """,
        ]),

        sprite("money", "Money", .float, "money, cash, dollar, rich, 錢, 金錢, 有錢, 鈔票, 花錢", [
            """
            vvvvvvvvvvvvvvvv
            vLGGGGGGGGGGGGLv
            vGGGGGvvvvGGGGGv
            vGGGGvGLLGvGGGGv
            vGLGGvLvvLvGGLGv
            vGGGGvGLLGvGGGGv
            vGGGGGvvvvGGGGGv
            vLGGGGGGGGGGGGLv
            vvvvvvvvvvvvvvvv
            """,
        ]),

        sprite("diamond", "Diamond", .twinkle, "diamond, jewel, ring, 鑽石, 戒指, 寶石", [
            """
            ...bbbbbbb...
            ..bcWcCcWcb..
            .bcWcCCCcWcb.
            bbbbbbbbbbbbb
            .bCcCCCCCcCb.
            ..bCcCCCcCb..
            ...bCcCcCb...
            ....bCcCb....
            .....bCb.....
            ......b......
            """,
        ]),

        sprite("crown", "Crown", .bounce, "king, queen, crown, prince, princess, royal, 國王, 女王, 王子, 公主, 皇冠", [
            """
            y.....y.....y
            yy...yYy...yy
            yYy.yYYYy.yYy
            yYYyYYYYYyYYy
            yYYYYYYYYYYYy
            yYYYYYRYYYYYy
            yYYYYRRRYYYYy
            yyyyyyyyyyyyy
            yCyyyRyyyCyyy
            yyyyyyyyyyyyy
            """,
        ]),

        sprite("key", "Key", .stay, "key, keys, lock, locked, unlock, 鑰匙, 鎖", [
            """
            .yyyy..........
            yYYYYy.........
            yY..Yyyyyyyyyyy
            yY..YYYYYYYYYYy
            yYYYYyyyyyYyYyy
            .yyyy.....y.y..
            """,
        ]),

        sprite("letter", "Letter", .fly, "letter, love letter, mail, envelope, 信封, 情書, 寫信, 來信", [
            """
            aaaaaaaaaaaaaaa
            aWgWWWWWWWWWgWa
            aWWgWWWWWWWgWWa
            aWWWgWWWWWgWWWa
            aWWWWgWRWgWWWWa
            aWWWWWgRgWWWWWa
            aWWWgWWWWWgWWWa
            aWWgWWWWWWWgWWa
            aWgWWWWWWWWWgWa
            aaaaaaaaaaaaaaa
            """,
        ]),

        sprite("camera", "Camera", .twinkle, "camera, photo, photograph, picture, selfie, 相機, 照片, 拍照", [
            """
            ....aaaa.......
            .kkkaaaakkkkkk.
            kaaaaaaaaaaRRak
            kaaaakkkkkaaaak
            kaaakbcbckkaaak
            kaaakcBBbckaaak
            kaaakbBBcbkaaak
            kaaakkbcbkkaaak
            kaaaakkkkkaaaak
            .kkkkkkkkkkkkk.
            """,
        ]),

        sprite("gift", "Gift", .bounce, "gift, christmas, 禮物, 聖誕節, 聖誕", [
            """
            ..RR.....RR..
            .R..R...R..R.
            .R...R.R...R.
            ..RRRRRRRRR..
            VVVVVVRVVVVVV
            VmmmmVRVmmmmV
            VVVVVVRVVVVVV
            .VmmmVRVmmmV.
            .VVVVVRVVVVV.
            .VmmmVRVmmmV.
            .VVVVVRVVVVV.
            .VVVVVRVVVVV.
            .uuuuuuuuuuu.
            """,
        ]),

        sprite("coffee", "Coffee", .stay, fps: 3, "coffee, cafe, espresso, latte, 咖啡", [
            """
            ..g...g.....
            ...g...g....
            ...g...g....
            ..g...g.....
            .WWWWWWWW...
            .WnnnnnnWgg.
            .WWWWWWWWg.g
            .WWWWWWWWg.g
            .WWWWWWWWgg.
            ..WWWWWW....
            gggggggggg..
            """,
            """
            ...g...g....
            ..g...g.....
            ..g...g.....
            ...g...g....
            .WWWWWWWW...
            .WnnnnnnWgg.
            .WWWWWWWWg.g
            .WWWWWWWWg.g
            .WWWWWWWWgg.
            ..WWWWWW....
            gggggggggg..
            """,
        ]),

        sprite("wine", "Wine", .stay, "wine, champagne, drink, drunk, cheers, 酒, 喝酒, 紅酒, 乾杯, 醉", [
            """
            .ggggggg.
            g.......g
            g.......g
            gRRRRRRRg
            gRrRRRRRg
            .gRRRRRg.
            ..gRRRg..
            ...ggg...
            ....g....
            ....g....
            ....g....
            ....g....
            ..ggggg..
            """,
        ]),

        sprite("balloon", "Balloon", .float, "balloon, birthday, 氣球, 生日", [
            """
            ..rrrrr..
            .rRRRRRr.
            rRpRRRRRr
            rRpRRRRRr
            rRRRRRRRr
            rRRRRRRRr
            .rRRRRRr.
            ..rRRRr..
            ...rRr...
            ....r....
            ....g....
            ...g.....
            ....g....
            .....g...
            ....g....
            """,
        ]),

        // MARK: Animals and fantasy

        sprite("cat", "Cat", .bounce, "cat, cats, kitty, kitten, meow, 貓, 貓咪, 小貓", [
            """
            .o.........o.
            .oo.......oo.
            .oPo.....oPo.
            .oOOooooOOOo.
            oOOOOOOOOOOOo
            oOOGKOOOGKOOo
            oOOGKOOOGKOOo
            oOOOOOPOOOOOo
            WWOOOoOoOOOWW
            .oOOOOOOOOOo.
            ..ooooooooo..
            """,
        ]),

        sprite("dog", "Dog", .bounce, "dog, dogs, puppy, doggy, woof, 狗, 狗狗, 小狗", [
            """
            .nn........nn.
            nNNn......nNNn
            nNNntttttttNNn
            nNNttttttttNNn
            nNttKttttKttNn
            .nttKttttKttn.
            ..tttttttttt..
            ..ttttKKtttt..
            ...tttKKttt...
            ...ttRRRttt...
            ....tRRttt....
            .....tttt.....
            """,
        ]),

        sprite("bird", "Bird", .fly, fps: 6, "bird, birds, fly, flying, flew, wings, 鳥, 小鳥, 飛, 飛翔, 翅膀", [
            """
            ...BB.......
            ....BB......
            .....BBBB...
            ...BBBBWKB..
            bBBBBBBBBBYY
            .bBBBBBBBB..
            ..bbBBBBb...
            .....b.b....
            """,
            """
            ............
            ............
            .......BBB..
            ...BBBBBWKB.
            bBBBBBBBBBYY
            .bBBBBBBBB..
            ...BBBBBb...
            ....BBb.....
            """,
        ]),

        sprite("butterfly", "Butterfly", .fly, fps: 5, "butterfly, butterflies, 蝴蝶", [
            """
            ....k...k....
            .uu..k.k..uu.
            uVVu.kkk.uVVu
            uVmVu.k.uVmVu
            uVVVVukuVVVVu
            .uVVVukuVVVu.
            ..uuuukuuuu..
            .uPPVukuVPPu.
            uPmPVukuVPmPu
            uPPPu.k.uPPPu
            .uuu.....uuu.
            """,
            """
            ....k...k....
            .....k.k.....
            ...uukkkuu...
            ..uVVukuVVu..
            ..uVmVkVmVu..
            ..uVVVkVVVu..
            ...uuukuuu...
            ...uPVkVPu...
            ..uPmPkPmPu..
            ..uPPukuPPu..
            ...uu...uu...
            """,
        ]),

        sprite("ghost", "Ghost", .float, "ghost, ghosts, haunted, haunt, spirit, 鬼, 幽靈, 鬼魂", [
            """
            ...gggggg...
            ..gWWWWWWg..
            .gWWWWWWWWg.
            gWWWWWWWWWWg
            gWWKKWWKKWWg
            gWWKKWWKKWWg
            gWWWWWWWWWWg
            gWWWWKKWWWWg
            gWWWWKKWWWWg
            gWWWWWWWWWWg
            gWWWWWWWWWWg
            gWgWWgWWgWWg
            .g.gg.gg.gg.
            """,
        ]),

        sprite("angel", "Angel", .float, "angel, angels, heaven, heavenly, halo, 天使, 天堂", [
            """
            .....yyyyy.....
            ....y.....y....
            .....yyyyy.....
            gg...........gg
            gWg..rr.rr..gWg
            gWWgrRRrRRrgWWg
            .gWWrRRRRRrWWg.
            ..gWgrRRRrgWg..
            ...gg.rRr.gg...
            .......r.......
            """,
        ]),
    ]

    private static func sprite(_ id: String, _ name: String, _ motion: PixelMotion, fps: Double = 4,
                               _ words: String, _ frames: [String]) -> PixelSprite {
        let colors = Dictionary(uniqueKeysWithValues: palette.map { ($0.key, $0.color) })
        do {
            return try PixelSprite(
                id: id, name: name, rows: frames.map { $0.split(separator: "\n").map(String.init) }, palette: colors,
                framesPerSecond: fps, words: words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                motion: motion)
        } catch {
            fatalError("Built-in sprite \(id) is malformed: \(error)")
        }
    }
}
