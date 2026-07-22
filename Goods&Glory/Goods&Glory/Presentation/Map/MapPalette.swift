//
//  MapPalette.swift
//  Goods&Glory
//
//  The map's ink. Kept apart from the scene so the art direction can be read
//  and adjusted without scrolling through camera and gesture code.
//

import UIKit

enum MapPalette {
    static let land = UIColor(red: 0.086, green: 0.157, blue: 0.247, alpha: 1)     // #16283F
    static let water = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 1)     // #0A1220
    /// One ink for every land edge, coast and border alike — the design draws
    /// them with a single stroke, so a faded coast would break the mosaic.
    static let coastline = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 1) // #2B4463
    /// Country borders — same ink family as the coast, softened so pinch-zoom
    /// does not sparkle on a hairline. Halo sits under the main stroke.
    static let boundary = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 0.70) // #2B4463
    static let boundaryHalo = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 0.22)
    static let city = UIColor(red: 0.122, green: 0.212, blue: 0.329, alpha: 1)      // #1F3654 fill
    static let cityStroke = UIColor(red: 0.478, green: 0.588, blue: 0.722, alpha: 1) // #7A96B8
    static let gold = UIColor(red: 1.0, green: 0.690, blue: 0.216, alpha: 1)         // #FFB037
    static let deadhead = UIColor(red: 1.0, green: 0.420, blue: 0.369, alpha: 0.85)  // #FF6B5E coral
    static let mint = UIColor(red: 0.310, green: 0.839, blue: 0.643, alpha: 1)       // #4FD6A4
    static let label = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.62)   // #F2EDE3
    static let onBrand = UIColor(red: 0.141, green: 0.082, blue: 0, alpha: 1)         // #241500
}

