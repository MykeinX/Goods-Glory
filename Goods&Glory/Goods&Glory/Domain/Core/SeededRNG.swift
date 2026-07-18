//
//  SeededRNG.swift
//  Goods&Glory
//
//  Deterministic randomness. All simulation randomness must flow through
//  seeds derived from stable identifiers via `SeedDerivation`, never from
//  SystemRandomNumberGenerator, wall clock, or hash ordering.
//
//  Derivation is stateless: seed(campaignSeed, "job_offers", tick) always
//  yields the same generator, independent of call order or platform.
//

import Foundation

/// SplitMix64 generator. Small, fast, well distributed, portable.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum SeedDerivation {
    /// FNV-1a over the campaign seed and stable string/int components.
    /// Components must be stable identifiers (catalog IDs, sequence numbers),
    /// never memory addresses or unordered collection contents.
    static func seed(_ campaignSeed: UInt64, _ components: SeedComponent...) -> UInt64 {
        var hash: UInt64 = 0xCBF29CE484222325
        func mix(byte: UInt8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001B3
        }
        withUnsafeBytes(of: campaignSeed.littleEndian) { $0.forEach(mix) }
        for component in components {
            switch component {
            case .string(let value):
                value.utf8.forEach(mix)
                mix(byte: 0) // separator
            case .int(let value):
                withUnsafeBytes(of: Int64(value).littleEndian) { $0.forEach(mix) }
            }
        }
        return hash
    }
}

enum SeedComponent: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case string(String)
    case int(Int)

    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
}
