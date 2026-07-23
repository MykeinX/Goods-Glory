//
//  MapPalette.swift
//  Goods&Glory
//
//  The map's ink. Kept apart from the scene so the art direction can be read
//  and adjusted without scrolling through camera and gesture code.
//

import UIKit

enum MapPalette {
    static let land = UIColor(red: 0.955, green: 0.958, blue: 0.970, alpha: 1)
    static let water = UIColor(red: 0.330, green: 0.570, blue: 0.910, alpha: 1)
    static let coastline = UIColor(red: 1, green: 1, blue: 1, alpha: 0.55)
    static let boundary = UIColor(red: 0.160, green: 0.310, blue: 0.500, alpha: 0.15)
    static let city = UIColor(red: 0.075, green: 0.165, blue: 0.275, alpha: 1)
    static let cityStroke = UIColor(red: 0.260, green: 0.475, blue: 0.690, alpha: 1)
    static let cityLabel = UIColor(red: 0.050, green: 0.125, blue: 0.220, alpha: 0.82)
    static let vehicleOutline = UIColor(red: 0.055, green: 0.110, blue: 0.180, alpha: 0.88)
    static let gold = UIColor(red: 1.0, green: 0.690, blue: 0.216, alpha: 1)         // #FFB037
    static let deadhead = UIColor(red: 1.0, green: 0.420, blue: 0.369, alpha: 0.85)  // #FF6B5E coral
    static let mint = UIColor(red: 0.310, green: 0.839, blue: 0.643, alpha: 1)       // #4FD6A4
    static let label = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.62)   // #F2EDE3
    static let onBrand = UIColor(red: 0.141, green: 0.082, blue: 0, alpha: 1)         // #241500
}
