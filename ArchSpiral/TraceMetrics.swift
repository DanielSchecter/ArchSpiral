//
//  TraceMetrics.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 2/2/26.
//

import Foundation

struct TraceMetrics {
    let date: Date

    // Accuracy
    // Legacy name retained; now combines within-band coverage with
    // a 95th-percentile severe-error cap.
    let percentWithinTolerance: Double   // 0..1
    let rmsePixels: Double               // px
    let tolerancePixels: Double          // px

    // Timing / speed
    let durationSeconds: Double
    let avgSpeedPxPerSec: Double

    // Quality
    // Legacy internal property name retained to avoid changing the calculation.
    // Displayed as Steadiness (0–100): higher = smoother/steadier.
    let shakinessScore0to100: Double
    let liftCount: Int
    let pauseCount: Int

    // Digital spiral score
    // Legacy internal property name retained to minimize code changes.
    // The value now ranges from 0 through 4.
    let icarSpiralScore1to4: Int

    var accuracyScore0to100: Double {
        100.0 * percentWithinTolerance
    }

    func asCopyText() -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short

        return """
        ArchSpiral Results
        Date: \(df.string(from: date))

        Accuracy: \(String(format: "%.0f", percentWithinTolerance * 100))%
        RMSE: \(String(format: "%.1f", rmsePixels)) px
        Tolerance: ±\(String(format: "%.1f", tolerancePixels)) px

        Time: \(String(format: "%.2f", durationSeconds)) s
        Avg speed: \(String(format: "%.0f", avgSpeedPxPerSec)) px/s

        Steadiness (0–100): \(Int(shakinessScore0to100))
        Lifts: \(liftCount)
        Pauses: \(pauseCount)

        Digital ICARS Spiral Score (0–4): \(icarSpiralScore1to4)
        """
    }
}
