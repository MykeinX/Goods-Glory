//
//  AppSettings.swift
//  Goods&Glory
//
//  Player preferences that outlive a campaign. Backed by UserDefaults, shared
//  by the UI and by GameSession (toast gating). Every option here changes real
//  behaviour — there are deliberately no decorative toggles.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let animatedTitleBackground = "settings.animatedTitleBackground"
        static let showsGameplayToasts = "settings.showsGameplayToasts"
        static let resumesPaused = "settings.resumesPaused"
        static let showsPerformanceOverlay = "settings.showsPerformanceOverlay"
    }

    private let defaults: UserDefaults

    /// Animates the title-screen route network. Turning it off freezes the
    /// canvas on a single frame, which is the cheapest the menu can be.
    var animatedTitleBackground: Bool {
        didSet { defaults.set(animatedTitleBackground, forKey: Key.animatedTitleBackground) }
    }

    /// In-game event toasts (deliveries, purchases, milestones).
    var showsGameplayToasts: Bool {
        didSet { defaults.set(showsGameplayToasts, forKey: Key.showsGameplayToasts) }
    }

    /// Whether Continue drops you into a paused world or straight into 1x time.
    var resumesPaused: Bool {
        didSet { defaults.set(resumesPaused, forKey: Key.resumesPaused) }
    }

    /// Developer HUD: SpriteKit's own fps / node / draw counters plus the
    /// simulation and snapshot timings. Debug builds only.
    var showsPerformanceOverlay: Bool {
        didSet { defaults.set(showsPerformanceOverlay, forKey: Key.showsPerformanceOverlay) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `object(forKey:) == nil` distinguishes "never set" from "set to false",
        // so first launch gets the intended defaults rather than all-off.
        self.animatedTitleBackground = defaults.object(forKey: Key.animatedTitleBackground) as? Bool ?? true
        self.showsGameplayToasts = defaults.object(forKey: Key.showsGameplayToasts) as? Bool ?? true
        self.resumesPaused = defaults.object(forKey: Key.resumesPaused) as? Bool ?? true
        self.showsPerformanceOverlay = defaults.bool(forKey: Key.showsPerformanceOverlay)
    }

    /// Marketing version and build, for the About row.
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
