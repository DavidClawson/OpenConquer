// MARK: - Map-selection data (MAPSEL.CPP)
//
// Presentation tables for the animated map-selection screen, transcribed from
// MAPSEL.CPP (the stats, country and coordinate tables were generated from the
// source; text ids are CONQUER.ENG indices = TXT_* values in conquer.h). Where
// each choice LEADS (dir/variant) is Core's CampaignGraph; this file only says
// how the screen looks and which click-map colour picks which choice.

enum MapSelectionData {
    struct Country {
        /// Per scenario direction [East, West].
        let choices: [Int]
        let start: [Int]        // progress-anim frame showing last mission's territories
        let cont: [Int]         // first frame of the crosshair/flash sequence
        let colors: [[Int]]     // CLICK_*.CPS index for each choice
        let shapes: [[Int]]     // COUNTRYE/A.SHP frame highlighted for each choice
    }

    /// CountryArray (MAPSEL.CPP:90-122), presentation columns only. Index = just-won row
    /// (GDI 1-14, Nod 15-26 = 14 + row). Per dir [E, W]: choices, start frame, cont frame,
    /// 3 colors, 3 shapes. Destinations (dir/variant) come from CampaignGraph.
    static let countries: [Country?] = [
        nil,  // 0
        Country(choices: [1, 1], start: [0, 0], cont: [3, 3], colors: [[0x95, 0x00, 0x00], [0x95, 0x00, 0x00]], shapes: [[17, 0, 0], [17, 0, 0]]),  // 1
        Country(choices: [1, 1], start: [16, 16], cont: [19, 19], colors: [[0x80, 0x00, 0x00], [0x80, 0x00, 0x00]], shapes: [[0, 0, 0], [0, 0, 0]]),  // 2
        Country(choices: [3, 3], start: [32, 32], cont: [35, 35], colors: [[0x81, 0x82, 0x83], [0x81, 0x82, 0x83]], shapes: [[3, 3, 1], [3, 3, 1]]),  // 3
        Country(choices: [2, 2], start: [48, 64], cont: [51, 67], colors: [[0x84, 0x85, 0x00], [0x86, 0x87, 0x00]], shapes: [[4, 4, 0], [2, 2, 0]]),  // 4
        Country(choices: [2, 2], start: [99, 99], cont: [102, 102], colors: [[0x88, 0x89, 0x00], [0x88, 0x89, 0x00]], shapes: [[7, 7, 0], [7, 7, 0]]),  // 5
        Country(choices: [2, 2], start: [80, 83], cont: [86, 86], colors: [[0x88, 0x89, 0x00], [0x88, 0x89, 0x00]], shapes: [[7, 7, 0], [7, 7, 0]]),  // 6
        Country(choices: [2, 2], start: [115, 0], cont: [118, 0], colors: [[0x8B, 0x8A, 0x00], [0x8B, 0x8A, 0x00]], shapes: [[6, 8, 0], [6, 8, 0]]),  // 7
        Country(choices: [1, 1], start: [131, 0], cont: [134, 0], colors: [[0x8C, 0x00, 0x00], [0x8C, 0x00, 0x00]], shapes: [[9, 0, 0], [9, 0, 0]]),  // 8
        Country(choices: [2, 1], start: [147, 0], cont: [150, 0], colors: [[0x8D, 0x8E, 0x00], [0x00, 0x00, 0x00]], shapes: [[10, 13, 0], [0, 0, 0]]),  // 9
        Country(choices: [1, 1], start: [163, 0], cont: [166, 0], colors: [[0x8F, 0x00, 0x00], [0x00, 0x00, 0x00]], shapes: [[16, 0, 0], [0, 0, 0]]),  // 10
        Country(choices: [2, 1], start: [179, 0], cont: [182, 0], colors: [[0x90, 0x91, 0x00], [0x00, 0x00, 0x00]], shapes: [[14, 15, 0], [0, 0, 0]]),  // 11
        Country(choices: [2, 1], start: [195, 0], cont: [198, 0], colors: [[0x92, 0x93, 0x00], [0x00, 0x00, 0x00]], shapes: [[12, 12, 0], [0, 0, 0]]),  // 12
        Country(choices: [1, 1], start: [211, 0], cont: [214, 0], colors: [[0x93, 0x00, 0x00], [0x00, 0x00, 0x00]], shapes: [[12, 0, 0], [0, 0, 0]]),  // 13
        Country(choices: [3, 1], start: [0, 0], cont: [3, 0], colors: [[0x81, 0x82, 0x83], [0x00, 0x00, 0x00]], shapes: [[0, 0, 0], [0, 0, 0]]),  // 14
        Country(choices: [2, 1], start: [0, 0], cont: [3, 0], colors: [[0x80, 0x81, 0x00], [0x00, 0x00, 0x00]], shapes: [[4, 4, 0], [0, 0, 0]]),  // 15
        Country(choices: [2, 1], start: [16, 0], cont: [19, 0], colors: [[0x82, 0x83, 0x00], [0x00, 0x00, 0x00]], shapes: [[6, 6, 0], [0, 0, 0]]),  // 16
        Country(choices: [2, 1], start: [32, 0], cont: [35, 0], colors: [[0x84, 0x85, 0x00], [0x00, 0x00, 0x00]], shapes: [[5, 5, 0], [0, 0, 0]]),  // 17
        Country(choices: [1, 1], start: [48, 0], cont: [51, 0], colors: [[0x86, 0x00, 0x00], [0x00, 0x00, 0x00]], shapes: [[0, 0, 0], [0, 0, 0]]),  // 18
        Country(choices: [3, 1], start: [64, 0], cont: [67, 0], colors: [[0x87, 0x88, 0x89], [0x00, 0x00, 0x00]], shapes: [[1, 2, 3], [0, 0, 0]]),  // 19
        Country(choices: [3, 1], start: [80, 0], cont: [83, 0], colors: [[0x8A, 0x8B, 0x8C], [0x00, 0x00, 0x00]], shapes: [[9, 7, 8], [0, 0, 0]]),  // 20
        Country(choices: [2, 1], start: [96, 0], cont: [99, 0], colors: [[0x8D, 0x8E, 0x00], [0x00, 0x00, 0x00]], shapes: [[10, 10, 0], [0, 0, 0]]),  // 21
        Country(choices: [1, 1], start: [112, 0], cont: [115, 0], colors: [[0xA0, 0x00, 0x00], [0x00, 0x00, 0x00]], shapes: [[4, 4, 0], [0, 0, 0]]),  // 22
        Country(choices: [2, 1], start: [128, 0], cont: [131, 0], colors: [[0x8F, 0x90, 0x00], [0x00, 0x00, 0x00]], shapes: [[11, 15, 0], [0, 0, 0]]),  // 23
        Country(choices: [2, 1], start: [144, 0], cont: [147, 0], colors: [[0x91, 0x92, 0x00], [0x00, 0x00, 0x00]], shapes: [[12, 16, 0], [0, 0, 0]]),  // 24
        Country(choices: [1, 1], start: [160, 0], cont: [163, 0], colors: [[0x93, 0x00, 0x00], [0x00, 0x00, 0x00]], shapes: [[13, 0, 0], [0, 0, 0]]),  // 25
        Country(choices: [3, 1], start: [0, 0], cont: [3, 0], colors: [[0x81, 0x82, 0x83], [0x00, 0x00, 0x00]], shapes: [[14, 0, 0], [0, 0, 0]]),  // 26
    ]
    static let countryX: [Int] = [195, 217, 115, 167, 244, 97, 130, 142, 171, 170, 139, 158, 180, 207, 177, 213, 201, 198, 69, 82, 105, 119, 184, 149, 187, 130, 153, 124, 162, 144, 145, 164, 166, 200, 201]
    static let countryY: [Int] = [35, 57, 82, 75, 93, 111, 108, 91, 100, 111, 120, 136, 136, 117, 158, 143, 167, 21, 45, 80, 75, 76, 31, 64, 69, 89, 88, 106, 115, 139, 168, 164, 183, 123, 154]
    static let gdiStatNames: [Int] = [506, 507, 508, 509, 510, 511, 512]
    static let nodStatNames: [Int] = [506, 513, 508, 509, 514, 515, 511, 516, 517]
    static let countryNames: [Int] = [518, 519, 520, 521, 522, 523, 524, 525, 526, 527, 528, 529, 530, 531, 532, 533, 534, 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547, 548, 549, 550, 551, 552]
    static let govtNames: [Int] = [553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564]
    static let armyNames: [Int] = [565, 566, 567, 568, 569, 570]
    static let militaryNames: [Int] = [571, 572, 573, 574, 575]
    /// GDIStats (MAPSEL.CPP:133): nameIndex, pop, area, capital, govt, gdp, conflict, military
    static let gdiStats: [[Int]] = [
        [0, 338, 374, 391, 0, 427, 457, 0],
        [1, 339, 375, 392, 1, 428, 458, 3],
        [1, 339, 375, 392, 1, 428, 459, 3],
        [2, 340, 376, 393, 0, 427, 460, 1],
        [3, 341, 377, 394, 3, 429, 461, 1],
        [3, 341, 377, 394, 3, 429, 461, 1],
        [4, 342, 378, 395, 2, 430, 462, 5],
        [4, 342, 378, 395, 2, 430, 463, 5],
        [5, 343, 379, 396, 0, 431, 464, 2],
        [5, 343, 379, 396, 0, 431, 464, 2],
        [6, 344, 380, 397, 0, 427, 465, 0],
        [7, 345, 381, 398, 4, 432, 457, 2],
        [8, 346, 382, 399, 4, 433, 467, 2],
        [9, 347, 383, 400, 0, 434, 468, 1],
        [10, 348, 384, 401, 0, 435, 469, 2],
        [11, 349, 385, 402, 5, 436, 470, 3],
        [12, 350, 386, 403, 6, 437, 471, 2],
        [13, 351, 387, 404, 0, 438, 472, 2],
        [14, 352, 388, 405, 0, 439, 473, 3],
        [14, 352, 388, 405, 0, 439, 474, 3],
        [15, 353, 389, 406, 7, 440, 475, 4],
        [34, 354, 390, 407, 0, 427, 476, 0],
    ]
    /// NodStats (MAPSEL.CPP:171): nameIndex, pop, expendable%, capital, govt, corruptible%, worth, conflict, military, probability%
    static let nodStats: [[Int]] = [
        [16, 355, 38, 408, 8, 86, 441, 477, 0, 23],
        [17, 356, 75, 409, 0, 18, 442, 478, 1, 82],
        [17, 356, 75, 409, 0, 18, 442, 479, 1, 82],
        [18, 357, 50, 410, 9, 52, 443, 480, 0, 72],
        [18, 357, 50, 410, 9, 52, 443, 481, 0, 72],
        [19, 358, 80, 411, 0, 85, 444, 482, 2, 35],
        [19, 358, 80, 411, 0, 85, 444, 483, 2, 35],
        [20, 359, 50, 412, 10, 48, 444, 484, 2, 24],
        [21, 360, 33, 413, 0, 28, 445, 485, 3, 67],
        [22, 361, 75, 414, 6, 17, 446, 486, 2, 80],
        [23, 362, 60, 415, 7, 93, 447, 487, 3, 50],
        [24, 363, 5, 416, 0, 84, 448, 488, 2, 22],
        [25, 364, 55, 417, 0, 48, 449, 489, 3, 62],
        [26, 365, 65, 418, 0, 41, 450, 490, 2, 49],
        [27, 366, 72, 419, 0, 74, 451, 491, 3, 54],
        [27, 366, 72, 419, 0, 74, 451, 492, 3, 54],
        [17, 367, 45, 420, 6, 3, 442, 493, 3, 100],
        [28, 368, 45, 421, 0, 63, 452, 494, 2, 66],
        [29, 369, 55, 422, 0, 27, 453, 495, 2, 68],
        [30, 370, 5, 423, 0, 65, 454, 496, 4, 74],
        [31, 371, 65, 424, 0, 52, 446, 497, 2, 84],
        [32, 372, 2, 425, 11, 12, 455, 498, 2, 92],
        [33, 373, 10, 426, 0, 8, 456, 499, 1, 100],
    ]
    static let readingImageData = 742  // TXT_READING_IMAGE_DATA
    static let analyzing = 743  // TXT_ANALYZING
    static let enhancingImageData = 744  // TXT_ENHANCING_IMAGE_DATA
    static let isolatingOperationalTheater = 745  // TXT_ISOLATING_OPERATIONAL_THEATER
    static let establishingTraditionalBoundaries = 746  // TXT_ESTABLISHING_TRADITIONAL_BOUNDARIES
    static let forVisualReference = 747  // TXT_FOR_VISUAL_REFERENCE
    static let enhancingImage = 748  // TXT_ENHANCING_IMAGE
    static let mapGdi = 500  // TXT_MAP_GDI
    static let mapNod = 501  // TXT_MAP_NOD
    static let mapLocate = 502  // TXT_MAP_LOCATE
    static let mapNextMission = 503  // TXT_MAP_NEXT_MISSION
    static let mapSelect = 504  // TXT_MAP_SELECT
    static let mapToAttack = 505  // TXT_MAP_TO_ATTACK
    static let mapClick2 = 576  // TXT_MAP_CLICK2

    /// "ANALYZING" is a literal in MAPSEL.CPP:409, not a string-table entry.
    static let analyzingLiteral = "ANALYZING"
}
