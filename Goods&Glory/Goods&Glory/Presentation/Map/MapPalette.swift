//
//  MapPalette.swift
//  Goods&Glory
//
//  The map's ink. Kept apart from the scene so the art direction can be read
//  and adjusted without scrolling through camera and gesture code.
//

import UIKit

enum MapPalette {
    // Median tones sampled from the supplied lossless board reference.
    static let land = UIColor(red: 0.949, green: 0.953, blue: 0.957, alpha: 1)      // #F2F3F4
    static let water = UIColor(red: 0.420, green: 0.631, blue: 0.984, alpha: 1)      // #6BA1FB
    // Barely-there bright rim on the coast; the lift now comes from landShadow.
    static let coastline = UIColor(red: 1, green: 1, blue: 1, alpha: 0.40)
    // Saturated blue shadow from the reference, not a muddy black drop shadow.
    static let landShadow = UIColor(red: 0.165, green: 0.400, blue: 0.855, alpha: 1) // #2A66DA
    static let city = UIColor(red: 0.075, green: 0.165, blue: 0.275, alpha: 1)
    // Metro-station fill: crisp white disc under a bold dark ring.
    static let station = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    // Clean white casing painted beneath every route line for a cut-out edge.
    static let routeCasing = UIColor(red: 1, green: 1, blue: 1, alpha: 0.92)
    static let cityLabel = UIColor(red: 0.050, green: 0.125, blue: 0.220, alpha: 0.82)
    static let vehicleOutline = UIColor(red: 0.055, green: 0.110, blue: 0.180, alpha: 0.88)
    static let gold = UIColor(red: 1.0, green: 0.690, blue: 0.216, alpha: 1)         // #FFB037
    static let deadhead = UIColor(red: 1.0, green: 0.420, blue: 0.369, alpha: 0.85)  // #FF6B5E coral
    static let mint = UIColor(red: 0.310, green: 0.839, blue: 0.643, alpha: 1)       // #4FD6A4
    static let label = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.62)   // #F2EDE3
    static let onBrand = UIColor(red: 0.141, green: 0.082, blue: 0, alpha: 1)         // #241500
}
