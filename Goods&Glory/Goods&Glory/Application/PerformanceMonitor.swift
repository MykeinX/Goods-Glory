//
//  PerformanceMonitor.swift
//  Goods&Glory
//
//  Cheap, always-on instrumentation for the two costs that will decide whether
//  this game still runs well at 300 vehicles: the simulation tick and the map
//  snapshot build. Deliberately NOT @Observable — the HUD polls it on a timer,
//  so recording a sample can never invalidate a SwiftUI view and the monitor
//  cannot become the thing it is measuring.
//

import Foundation
import QuartzCore

@MainActor
final class PerformanceMonitor {
    static let shared = PerformanceMonitor()

    /// Exponential moving averages, in milliseconds.
    private(set) var tickMilliseconds: Double = 0
    private(set) var snapshotMilliseconds: Double = 0
    /// Worst sample seen since the last reset — averages hide the stalls.
    private(set) var peakTickMilliseconds: Double = 0
    private(set) var peakSnapshotMilliseconds: Double = 0
    private(set) var saveMilliseconds: Double = 0

    private let smoothing = 0.15

    private func blend(_ average: Double, _ sample: Double) -> Double {
        average == 0 ? sample : average + (sample - average) * smoothing
    }

    func recordTick(_ seconds: Double) {
        let ms = seconds * 1000
        tickMilliseconds = blend(tickMilliseconds, ms)
        peakTickMilliseconds = max(peakTickMilliseconds, ms)
    }

    func recordSnapshot(_ seconds: Double) {
        let ms = seconds * 1000
        snapshotMilliseconds = blend(snapshotMilliseconds, ms)
        peakSnapshotMilliseconds = max(peakSnapshotMilliseconds, ms)
    }

    func recordSave(_ seconds: Double) {
        saveMilliseconds = blend(saveMilliseconds, seconds * 1000)
    }

    func resetPeaks() {
        peakTickMilliseconds = 0
        peakSnapshotMilliseconds = 0
    }
}
