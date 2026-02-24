import Foundation

// MARK: - Map Cell

struct MapCell {
    let templateType: UInt8   // 0-215 valid, 255 = TEMPLATE_NONE (clear terrain)
    let iconIndex: UInt8      // icon index within the template's ICN tileset
}

// MARK: - Template Info

struct TemplateInfo {
    let icnName: String   // e.g. "CLEAR1", "W2", "BRIDGE1"
    let width: Int        // template width in tiles
    let height: Int       // template height in tiles
}

// MARK: - BIN Map Loader

/// Load a scenario BIN file from the MIX archives.
/// BIN format: 8192 bytes = 4096 cells (64x64 grid), 2 bytes per cell.
/// Byte 0 = TemplateType, Byte 1 = icon index within template.
func loadMap(_ name: String, from mixManager: MIXFileManager) -> [MapCell]? {
    guard let data = mixManager.retrieve(name) else {
        print("MapLoader: Could not find \(name) in MIX archives")
        return nil
    }

    guard data.count >= 8192 else {
        print("MapLoader: \(name) too small (\(data.count) bytes, expected 8192)")
        return nil
    }

    let baseIndex = data.startIndex
    var cells = [MapCell]()
    cells.reserveCapacity(4096)

    for i in 0..<4096 {
        let templateType = data[baseIndex + i * 2]
        let iconIndex = data[baseIndex + i * 2 + 1]
        cells.append(MapCell(templateType: templateType, iconIndex: iconIndex))
    }

    print("MapLoader: Loaded \(name) - \(cells.count) cells")
    return cells
}

// MARK: - Template Table (216 entries from cdata.cpp)
// Extracted from Vanilla-Conquer/tiberiandawn/cdata.cpp Pointers[] array.
// Each entry: (INI name, width in tiles, height in tiles)

let templateTable: [TemplateInfo] = [
    TemplateInfo(icnName: "CLEAR1", width: 1, height: 1),     // 0   TEMPLATE_CLEAR1
    TemplateInfo(icnName: "W1", width: 1, height: 1),         // 1   TEMPLATE_WATER
    TemplateInfo(icnName: "W2", width: 2, height: 2),         // 2   TEMPLATE_WATER2
    TemplateInfo(icnName: "SH1", width: 3, height: 3),        // 3   TEMPLATE_SHORE1
    TemplateInfo(icnName: "SH2", width: 3, height: 3),        // 4   TEMPLATE_SHORE2
    TemplateInfo(icnName: "SH3", width: 1, height: 1),        // 5   TEMPLATE_SHORE3
    TemplateInfo(icnName: "SH4", width: 2, height: 1),        // 6   TEMPLATE_SHORE4
    TemplateInfo(icnName: "SH5", width: 3, height: 3),        // 7   TEMPLATE_SHORE5
    TemplateInfo(icnName: "SH11", width: 3, height: 3),       // 8   TEMPLATE_SHORE11
    TemplateInfo(icnName: "SH12", width: 3, height: 3),       // 9   TEMPLATE_SHORE12
    TemplateInfo(icnName: "SH13", width: 3, height: 3),       // 10  TEMPLATE_SHORE13
    TemplateInfo(icnName: "SH14", width: 3, height: 3),       // 11  TEMPLATE_SHORE14
    TemplateInfo(icnName: "SH15", width: 3, height: 3),       // 12  TEMPLATE_SHORE15
    TemplateInfo(icnName: "S01", width: 2, height: 2),        // 13  TEMPLATE_SLOPE1
    TemplateInfo(icnName: "S02", width: 2, height: 3),        // 14  TEMPLATE_SLOPE2
    TemplateInfo(icnName: "S03", width: 2, height: 2),        // 15  TEMPLATE_SLOPE3
    TemplateInfo(icnName: "S04", width: 2, height: 2),        // 16  TEMPLATE_SLOPE4
    TemplateInfo(icnName: "S05", width: 2, height: 2),        // 17  TEMPLATE_SLOPE5
    TemplateInfo(icnName: "S06", width: 2, height: 3),        // 18  TEMPLATE_SLOPE6
    TemplateInfo(icnName: "S07", width: 2, height: 2),        // 19  TEMPLATE_SLOPE7
    TemplateInfo(icnName: "S08", width: 2, height: 2),        // 20  TEMPLATE_SLOPE8
    TemplateInfo(icnName: "S09", width: 3, height: 2),        // 21  TEMPLATE_SLOPE9
    TemplateInfo(icnName: "S10", width: 2, height: 2),        // 22  TEMPLATE_SLOPE10
    TemplateInfo(icnName: "S11", width: 2, height: 2),        // 23  TEMPLATE_SLOPE11
    TemplateInfo(icnName: "S12", width: 2, height: 2),        // 24  TEMPLATE_SLOPE12
    TemplateInfo(icnName: "S13", width: 3, height: 2),        // 25  TEMPLATE_SLOPE13
    TemplateInfo(icnName: "S14", width: 2, height: 2),        // 26  TEMPLATE_SLOPE14
    TemplateInfo(icnName: "S15", width: 2, height: 2),        // 27  TEMPLATE_SLOPE15
    TemplateInfo(icnName: "S16", width: 2, height: 3),        // 28  TEMPLATE_SLOPE16
    TemplateInfo(icnName: "S17", width: 2, height: 2),        // 29  TEMPLATE_SLOPE17
    TemplateInfo(icnName: "S18", width: 2, height: 2),        // 30  TEMPLATE_SLOPE18
    TemplateInfo(icnName: "S19", width: 2, height: 2),        // 31  TEMPLATE_SLOPE19
    TemplateInfo(icnName: "S20", width: 2, height: 3),        // 32  TEMPLATE_SLOPE20
    TemplateInfo(icnName: "S21", width: 1, height: 2),        // 33  TEMPLATE_SLOPE21
    TemplateInfo(icnName: "S22", width: 2, height: 1),        // 34  TEMPLATE_SLOPE22
    TemplateInfo(icnName: "S23", width: 3, height: 2),        // 35  TEMPLATE_SLOPE23
    TemplateInfo(icnName: "S24", width: 2, height: 2),        // 36  TEMPLATE_SLOPE24
    TemplateInfo(icnName: "S25", width: 2, height: 2),        // 37  TEMPLATE_SLOPE25
    TemplateInfo(icnName: "S26", width: 2, height: 2),        // 38  TEMPLATE_SLOPE26
    TemplateInfo(icnName: "S27", width: 3, height: 2),        // 39  TEMPLATE_SLOPE27
    TemplateInfo(icnName: "S28", width: 2, height: 2),        // 40  TEMPLATE_SLOPE28
    TemplateInfo(icnName: "S29", width: 2, height: 2),        // 41  TEMPLATE_SLOPE29
    TemplateInfo(icnName: "S30", width: 2, height: 2),        // 42  TEMPLATE_SLOPE30
    TemplateInfo(icnName: "S31", width: 2, height: 2),        // 43  TEMPLATE_SLOPE31
    TemplateInfo(icnName: "S32", width: 2, height: 2),        // 44  TEMPLATE_SLOPE32
    TemplateInfo(icnName: "S33", width: 2, height: 2),        // 45  TEMPLATE_SLOPE33
    TemplateInfo(icnName: "S34", width: 2, height: 2),        // 46  TEMPLATE_SLOPE34
    TemplateInfo(icnName: "S35", width: 2, height: 2),        // 47  TEMPLATE_SLOPE35
    TemplateInfo(icnName: "S36", width: 2, height: 2),        // 48  TEMPLATE_SLOPE36
    TemplateInfo(icnName: "S37", width: 2, height: 2),        // 49  TEMPLATE_SLOPE37
    TemplateInfo(icnName: "S38", width: 2, height: 2),        // 50  TEMPLATE_SLOPE38
    TemplateInfo(icnName: "SH32", width: 3, height: 3),       // 51  TEMPLATE_SHORE32
    TemplateInfo(icnName: "SH33", width: 3, height: 3),       // 52  TEMPLATE_SHORE33
    TemplateInfo(icnName: "SH20", width: 4, height: 1),       // 53  TEMPLATE_SHORE20
    TemplateInfo(icnName: "SH21", width: 3, height: 1),       // 54  TEMPLATE_SHORE21
    TemplateInfo(icnName: "SH22", width: 6, height: 2),       // 55  TEMPLATE_SHORE22
    TemplateInfo(icnName: "SH23", width: 2, height: 2),       // 56  TEMPLATE_SHORE23
    TemplateInfo(icnName: "BR1", width: 1, height: 1),        // 57  TEMPLATE_BRUSH1
    TemplateInfo(icnName: "BR2", width: 1, height: 1),        // 58  TEMPLATE_BRUSH2
    TemplateInfo(icnName: "BR3", width: 1, height: 1),        // 59  TEMPLATE_BRUSH3
    TemplateInfo(icnName: "BR4", width: 1, height: 1),        // 60  TEMPLATE_BRUSH4
    TemplateInfo(icnName: "BR5", width: 1, height: 1),        // 61  TEMPLATE_BRUSH5
    TemplateInfo(icnName: "BR6", width: 2, height: 2),        // 62  TEMPLATE_BRUSH6
    TemplateInfo(icnName: "BR7", width: 2, height: 2),        // 63  TEMPLATE_BRUSH7
    TemplateInfo(icnName: "BR8", width: 3, height: 2),        // 64  TEMPLATE_BRUSH8
    TemplateInfo(icnName: "BR9", width: 3, height: 2),        // 65  TEMPLATE_BRUSH9
    TemplateInfo(icnName: "BR10", width: 2, height: 1),       // 66  TEMPLATE_BRUSH10
    TemplateInfo(icnName: "P01", width: 1, height: 1),        // 67  TEMPLATE_PATCH1
    TemplateInfo(icnName: "P02", width: 1, height: 1),        // 68  TEMPLATE_PATCH2
    TemplateInfo(icnName: "P03", width: 1, height: 1),        // 69  TEMPLATE_PATCH3
    TemplateInfo(icnName: "P04", width: 1, height: 1),        // 70  TEMPLATE_PATCH4
    TemplateInfo(icnName: "P05", width: 2, height: 2),        // 71  TEMPLATE_PATCH5
    TemplateInfo(icnName: "P06", width: 6, height: 4),        // 72  TEMPLATE_PATCH6
    TemplateInfo(icnName: "P07", width: 4, height: 2),        // 73  TEMPLATE_PATCH7
    TemplateInfo(icnName: "P08", width: 3, height: 2),        // 74  TEMPLATE_PATCH8
    TemplateInfo(icnName: "SH16", width: 3, height: 2),       // 75  TEMPLATE_SHORE16
    TemplateInfo(icnName: "SH17", width: 2, height: 2),       // 76  TEMPLATE_SHORE17
    TemplateInfo(icnName: "SH18", width: 2, height: 2),       // 77  TEMPLATE_SHORE18
    TemplateInfo(icnName: "SH19", width: 3, height: 2),       // 78  TEMPLATE_SHORE19
    TemplateInfo(icnName: "P13", width: 3, height: 2),        // 79  TEMPLATE_PATCH13
    TemplateInfo(icnName: "P14", width: 2, height: 1),        // 80  TEMPLATE_PATCH14
    TemplateInfo(icnName: "P15", width: 4, height: 2),        // 81  TEMPLATE_PATCH15
    TemplateInfo(icnName: "B1", width: 1, height: 1),         // 82  TEMPLATE_BOULDER1
    TemplateInfo(icnName: "B2", width: 2, height: 1),         // 83  TEMPLATE_BOULDER2
    TemplateInfo(icnName: "B3", width: 3, height: 1),         // 84  TEMPLATE_BOULDER3
    TemplateInfo(icnName: "B4", width: 1, height: 1),         // 85  TEMPLATE_BOULDER4
    TemplateInfo(icnName: "B5", width: 1, height: 1),         // 86  TEMPLATE_BOULDER5
    TemplateInfo(icnName: "B6", width: 1, height: 1),         // 87  TEMPLATE_BOULDER6
    TemplateInfo(icnName: "SH6", width: 3, height: 3),        // 88  TEMPLATE_SHORE6
    TemplateInfo(icnName: "SH7", width: 2, height: 2),        // 89  TEMPLATE_SHORE7
    TemplateInfo(icnName: "SH8", width: 3, height: 3),        // 90  TEMPLATE_SHORE8
    TemplateInfo(icnName: "SH9", width: 3, height: 3),        // 91  TEMPLATE_SHORE9
    TemplateInfo(icnName: "SH10", width: 2, height: 2),       // 92  TEMPLATE_SHORE10
    TemplateInfo(icnName: "D01", width: 2, height: 2),        // 93  TEMPLATE_ROAD1
    TemplateInfo(icnName: "D02", width: 2, height: 2),        // 94  TEMPLATE_ROAD2
    TemplateInfo(icnName: "D03", width: 1, height: 2),        // 95  TEMPLATE_ROAD3
    TemplateInfo(icnName: "D04", width: 2, height: 2),        // 96  TEMPLATE_ROAD4
    TemplateInfo(icnName: "D05", width: 3, height: 4),        // 97  TEMPLATE_ROAD5
    TemplateInfo(icnName: "D06", width: 2, height: 3),        // 98  TEMPLATE_ROAD6
    TemplateInfo(icnName: "D07", width: 3, height: 2),        // 99  TEMPLATE_ROAD7
    TemplateInfo(icnName: "D08", width: 3, height: 2),        // 100 TEMPLATE_ROAD8
    TemplateInfo(icnName: "D09", width: 4, height: 3),        // 101 TEMPLATE_ROAD9
    TemplateInfo(icnName: "D10", width: 4, height: 2),        // 102 TEMPLATE_ROAD10
    TemplateInfo(icnName: "D11", width: 2, height: 3),        // 103 TEMPLATE_ROAD11
    TemplateInfo(icnName: "D12", width: 2, height: 2),        // 104 TEMPLATE_ROAD12
    TemplateInfo(icnName: "D13", width: 4, height: 3),        // 105 TEMPLATE_ROAD13
    TemplateInfo(icnName: "D14", width: 3, height: 3),        // 106 TEMPLATE_ROAD14
    TemplateInfo(icnName: "D15", width: 3, height: 3),        // 107 TEMPLATE_ROAD15
    TemplateInfo(icnName: "D16", width: 3, height: 3),        // 108 TEMPLATE_ROAD16
    TemplateInfo(icnName: "D17", width: 3, height: 2),        // 109 TEMPLATE_ROAD17
    TemplateInfo(icnName: "D18", width: 3, height: 3),        // 110 TEMPLATE_ROAD18
    TemplateInfo(icnName: "D19", width: 3, height: 3),        // 111 TEMPLATE_ROAD19
    TemplateInfo(icnName: "D20", width: 3, height: 3),        // 112 TEMPLATE_ROAD20
    TemplateInfo(icnName: "D21", width: 3, height: 2),        // 113 TEMPLATE_ROAD21
    TemplateInfo(icnName: "D22", width: 3, height: 3),        // 114 TEMPLATE_ROAD22
    TemplateInfo(icnName: "D23", width: 3, height: 3),        // 115 TEMPLATE_ROAD23
    TemplateInfo(icnName: "D24", width: 3, height: 3),        // 116 TEMPLATE_ROAD24
    TemplateInfo(icnName: "D25", width: 3, height: 3),        // 117 TEMPLATE_ROAD25
    TemplateInfo(icnName: "D26", width: 2, height: 2),        // 118 TEMPLATE_ROAD26
    TemplateInfo(icnName: "D27", width: 2, height: 2),        // 119 TEMPLATE_ROAD27
    TemplateInfo(icnName: "D28", width: 2, height: 2),        // 120 TEMPLATE_ROAD28
    TemplateInfo(icnName: "D29", width: 2, height: 2),        // 121 TEMPLATE_ROAD29
    TemplateInfo(icnName: "D30", width: 2, height: 2),        // 122 TEMPLATE_ROAD30
    TemplateInfo(icnName: "D31", width: 2, height: 2),        // 123 TEMPLATE_ROAD31
    TemplateInfo(icnName: "D32", width: 2, height: 2),        // 124 TEMPLATE_ROAD32
    TemplateInfo(icnName: "D33", width: 2, height: 2),        // 125 TEMPLATE_ROAD33
    TemplateInfo(icnName: "D34", width: 3, height: 3),        // 126 TEMPLATE_ROAD34
    TemplateInfo(icnName: "D35", width: 3, height: 3),        // 127 TEMPLATE_ROAD35
    TemplateInfo(icnName: "D36", width: 2, height: 2),        // 128 TEMPLATE_ROAD36
    TemplateInfo(icnName: "D37", width: 2, height: 2),        // 129 TEMPLATE_ROAD37
    TemplateInfo(icnName: "D38", width: 2, height: 2),        // 130 TEMPLATE_ROAD38
    TemplateInfo(icnName: "D39", width: 2, height: 2),        // 131 TEMPLATE_ROAD39
    TemplateInfo(icnName: "D40", width: 2, height: 2),        // 132 TEMPLATE_ROAD40
    TemplateInfo(icnName: "D41", width: 2, height: 2),        // 133 TEMPLATE_ROAD41
    TemplateInfo(icnName: "D42", width: 2, height: 2),        // 134 TEMPLATE_ROAD42
    TemplateInfo(icnName: "D43", width: 2, height: 2),        // 135 TEMPLATE_ROAD43
    TemplateInfo(icnName: "RV01", width: 5, height: 4),       // 136 TEMPLATE_RIVER1
    TemplateInfo(icnName: "RV02", width: 5, height: 3),       // 137 TEMPLATE_RIVER2
    TemplateInfo(icnName: "RV03", width: 4, height: 4),       // 138 TEMPLATE_RIVER3
    TemplateInfo(icnName: "RV04", width: 4, height: 4),       // 139 TEMPLATE_RIVER4
    TemplateInfo(icnName: "RV05", width: 3, height: 3),       // 140 TEMPLATE_RIVER5
    TemplateInfo(icnName: "RV06", width: 3, height: 2),       // 141 TEMPLATE_RIVER6
    TemplateInfo(icnName: "RV07", width: 3, height: 2),       // 142 TEMPLATE_RIVER7
    TemplateInfo(icnName: "RV08", width: 2, height: 2),       // 143 TEMPLATE_RIVER8
    TemplateInfo(icnName: "RV09", width: 2, height: 2),       // 144 TEMPLATE_RIVER9
    TemplateInfo(icnName: "RV10", width: 2, height: 2),       // 145 TEMPLATE_RIVER10
    TemplateInfo(icnName: "RV11", width: 2, height: 2),       // 146 TEMPLATE_RIVER11
    TemplateInfo(icnName: "RV12", width: 3, height: 4),       // 147 TEMPLATE_RIVER12
    TemplateInfo(icnName: "RV13", width: 4, height: 4),       // 148 TEMPLATE_RIVER13
    TemplateInfo(icnName: "RV14", width: 4, height: 3),       // 149 TEMPLATE_RIVER14
    TemplateInfo(icnName: "RV15", width: 4, height: 3),       // 150 TEMPLATE_RIVER15
    TemplateInfo(icnName: "RV16", width: 6, height: 4),       // 151 TEMPLATE_RIVER16
    TemplateInfo(icnName: "RV17", width: 6, height: 5),       // 152 TEMPLATE_RIVER17
    TemplateInfo(icnName: "RV18", width: 4, height: 4),       // 153 TEMPLATE_RIVER18
    TemplateInfo(icnName: "RV19", width: 4, height: 4),       // 154 TEMPLATE_RIVER19
    TemplateInfo(icnName: "RV20", width: 6, height: 8),       // 155 TEMPLATE_RIVER20
    TemplateInfo(icnName: "RV21", width: 5, height: 8),       // 156 TEMPLATE_RIVER21
    TemplateInfo(icnName: "RV22", width: 3, height: 3),       // 157 TEMPLATE_RIVER22
    TemplateInfo(icnName: "RV23", width: 3, height: 3),       // 158 TEMPLATE_RIVER23
    TemplateInfo(icnName: "RV24", width: 3, height: 3),       // 159 TEMPLATE_RIVER24
    TemplateInfo(icnName: "RV25", width: 3, height: 3),       // 160 TEMPLATE_RIVER25
    TemplateInfo(icnName: "FORD1", width: 3, height: 3),      // 161 TEMPLATE_FORD1
    TemplateInfo(icnName: "FORD2", width: 3, height: 3),      // 162 TEMPLATE_FORD2
    TemplateInfo(icnName: "FALLS1", width: 3, height: 3),     // 163 TEMPLATE_FALLS1
    TemplateInfo(icnName: "FALLS2", width: 3, height: 2),     // 164 TEMPLATE_FALLS2
    TemplateInfo(icnName: "BRIDGE1", width: 4, height: 4),    // 165 TEMPLATE_BRIDGE1
    TemplateInfo(icnName: "BRIDGE1D", width: 4, height: 4),   // 166 TEMPLATE_BRIDGE1D
    TemplateInfo(icnName: "BRIDGE2", width: 5, height: 5),    // 167 TEMPLATE_BRIDGE2
    TemplateInfo(icnName: "BRIDGE2D", width: 5, height: 5),   // 168 TEMPLATE_BRIDGE2D
    TemplateInfo(icnName: "BRIDGE3", width: 6, height: 5),    // 169 TEMPLATE_BRIDGE3
    TemplateInfo(icnName: "BRIDGE3D", width: 6, height: 5),   // 170 TEMPLATE_BRIDGE3D
    TemplateInfo(icnName: "BRIDGE4", width: 6, height: 4),    // 171 TEMPLATE_BRIDGE4
    TemplateInfo(icnName: "BRIDGE4D", width: 6, height: 4),   // 172 TEMPLATE_BRIDGE4D
    TemplateInfo(icnName: "SH24", width: 3, height: 3),       // 173 TEMPLATE_SHORE24
    TemplateInfo(icnName: "SH25", width: 3, height: 2),       // 174 TEMPLATE_SHORE25
    TemplateInfo(icnName: "SH26", width: 3, height: 2),       // 175 TEMPLATE_SHORE26
    TemplateInfo(icnName: "SH27", width: 4, height: 1),       // 176 TEMPLATE_SHORE27
    TemplateInfo(icnName: "SH28", width: 3, height: 1),       // 177 TEMPLATE_SHORE28
    TemplateInfo(icnName: "SH29", width: 6, height: 2),       // 178 TEMPLATE_SHORE29
    TemplateInfo(icnName: "SH30", width: 2, height: 2),       // 179 TEMPLATE_SHORE30
    TemplateInfo(icnName: "SH31", width: 3, height: 3),       // 180 TEMPLATE_SHORE31
    TemplateInfo(icnName: "P16", width: 2, height: 2),        // 181 TEMPLATE_PATCH16
    TemplateInfo(icnName: "P17", width: 4, height: 2),        // 182 TEMPLATE_PATCH17
    TemplateInfo(icnName: "P18", width: 4, height: 3),        // 183 TEMPLATE_PATCH18
    TemplateInfo(icnName: "P19", width: 4, height: 3),        // 184 TEMPLATE_PATCH19
    TemplateInfo(icnName: "P20", width: 4, height: 3),        // 185 TEMPLATE_PATCH20
    TemplateInfo(icnName: "SH34", width: 3, height: 3),       // 186 TEMPLATE_SHORE34
    TemplateInfo(icnName: "SH35", width: 3, height: 3),       // 187 TEMPLATE_SHORE35
    TemplateInfo(icnName: "SH36", width: 1, height: 1),       // 188 TEMPLATE_SHORE36
    TemplateInfo(icnName: "SH37", width: 1, height: 1),       // 189 TEMPLATE_SHORE37
    TemplateInfo(icnName: "SH38", width: 1, height: 1),       // 190 TEMPLATE_SHORE38
    TemplateInfo(icnName: "SH39", width: 1, height: 1),       // 191 TEMPLATE_SHORE39
    TemplateInfo(icnName: "SH40", width: 3, height: 3),       // 192 TEMPLATE_SHORE40
    TemplateInfo(icnName: "SH41", width: 3, height: 3),       // 193 TEMPLATE_SHORE41
    TemplateInfo(icnName: "SH42", width: 1, height: 2),       // 194 TEMPLATE_SHORE42
    TemplateInfo(icnName: "SH43", width: 1, height: 3),       // 195 TEMPLATE_SHORE43
    TemplateInfo(icnName: "SH44", width: 1, height: 3),       // 196 TEMPLATE_SHORE44
    TemplateInfo(icnName: "SH45", width: 1, height: 2),       // 197 TEMPLATE_SHORE45
    TemplateInfo(icnName: "SH46", width: 3, height: 3),       // 198 TEMPLATE_SHORE46
    TemplateInfo(icnName: "SH47", width: 3, height: 3),       // 199 TEMPLATE_SHORE47
    TemplateInfo(icnName: "SH48", width: 3, height: 3),       // 200 TEMPLATE_SHORE48
    TemplateInfo(icnName: "SH49", width: 3, height: 3),       // 201 TEMPLATE_SHORE49
    TemplateInfo(icnName: "SH50", width: 4, height: 3),       // 202 TEMPLATE_SHORE50
    TemplateInfo(icnName: "SH51", width: 4, height: 3),       // 203 TEMPLATE_SHORE51
    TemplateInfo(icnName: "SH52", width: 4, height: 3),       // 204 TEMPLATE_SHORE52
    TemplateInfo(icnName: "SH53", width: 4, height: 3),       // 205 TEMPLATE_SHORE53
    TemplateInfo(icnName: "SH54", width: 3, height: 2),       // 206 TEMPLATE_SHORE54
    TemplateInfo(icnName: "SH55", width: 3, height: 2),       // 207 TEMPLATE_SHORE55
    TemplateInfo(icnName: "SH56", width: 3, height: 2),       // 208 TEMPLATE_SHORE56
    TemplateInfo(icnName: "SH57", width: 3, height: 2),       // 209 TEMPLATE_SHORE57
    TemplateInfo(icnName: "SH58", width: 2, height: 3),       // 210 TEMPLATE_SHORE58
    TemplateInfo(icnName: "SH59", width: 2, height: 3),       // 211 TEMPLATE_SHORE59
    TemplateInfo(icnName: "SH60", width: 2, height: 3),       // 212 TEMPLATE_SHORE60
    TemplateInfo(icnName: "SH61", width: 2, height: 3),       // 213 TEMPLATE_SHORE61
    TemplateInfo(icnName: "SH62", width: 6, height: 1),       // 214 TEMPLATE_SHORE62
    TemplateInfo(icnName: "SH63", width: 4, height: 1),       // 215 TEMPLATE_SHORE63
]
