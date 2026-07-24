//
//  MapPalette.swift
//  Goods&Glory
//
//  The map's ink. Kept apart from the scene so the art direction can be read
//  and adjusted without scrolling through camera and gesture code.
//
//  Matches Theme "Gece Haritası": deep navy sea, lifted slate land, warm
//  off-white labels — a night logistics board, not the light reference PNG.
//

import UIKit

enum MapPalette {
    /// Deep night sea — same family as `Theme.backgroundTop`.
    static let water = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 1)      // #0A1220
    /// Lifted continent fill so mass reads against the sea without going light.
    static let land = UIColor(red: 0.102, green: 0.165, blue: 0.255, alpha: 1)       // #1A2A41
    /// Cool hairline coast rim (sky accent, low alpha).
    static let coastline = UIColor(red: 0.341, green: 0.698, blue: 1.0, alpha: 0.22) // #57B2FF
    /// Darker under-plate for a soft board lift — not a bright blue drop.
    static let landShadow = UIColor(red: 0.012, green: 0.024, blue: 0.047, alpha: 1) // #03060C
    /// Soft label ink for city names on night land.
    static let cityLabel = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.9)
    /// Outer city ring — lighter lifted slate, reads as a thin halo band.
    static let stationRing = UIColor(red: 0.255, green: 0.365, blue: 0.522, alpha: 1) // #415D85
    /// Inner city disc — deeper slate (darker core).
    static let station = UIColor(red: 0.071, green: 0.118, blue: 0.196, alpha: 1)    // #121E32
    /// Legacy alias used by selection / misc strokes.
    static let city = cityLabel
    /// Soft dark casing under route ink so accent strokes cut cleanly at night.
    static let routeCasing = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 0.88)
    static let vehicleOutline = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 0.92)
    static let gold = UIColor(red: 1.0, green: 0.690, blue: 0.216, alpha: 1)         // #FFB037
    static let deadhead = UIColor(red: 1.0, green: 0.420, blue: 0.369, alpha: 0.85)  // #FF6B5E coral
    static let mint = UIColor(red: 0.310, green: 0.839, blue: 0.643, alpha: 1)       // #4FD6A4
    static let label = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.62)   // #F2EDE3
    static let onBrand = UIColor(red: 0.141, green: 0.082, blue: 0, alpha: 1)         // #241500
}
