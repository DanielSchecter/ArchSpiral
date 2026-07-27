//
//  MetricsPanel.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 2/2/26.
//

import SwiftUI

struct MetricsPanel: View {
    let metrics: TraceMetrics
    let inputMode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Results")
                .font(.headline)

            Text("Input Mode: \(inputMode)")

            Text(String(format: "Accuracy: %.0f%% (RMSE %.1f px, tol ±%.1f px)",
                        metrics.percentWithinTolerance * 100,
                        metrics.rmsePixels,
                        metrics.tolerancePixels))

            Text(String(format: "Time: %.2f s   Avg speed: %.0f px/s",
                        metrics.durationSeconds,
                        metrics.avgSpeedPxPerSec))

            Text("Steadiness (0–100): \(Int(metrics.shakinessScore0to100))")

            Text("Lifts: \(metrics.liftCount)   Pauses: \(metrics.pauseCount)")

            Text("Digital ICARS Spiral Score (0–4): \(metrics.icarSpiralScore1to4)")
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    MetricsPanel(
        metrics: TraceMetrics(
            date: Date(),
            percentWithinTolerance: 0.82,
            rmsePixels: 9.6,
            tolerancePixels: 20.0,
            durationSeconds: 12.4,
            avgSpeedPxPerSec: 410,
            shakinessScore0to100: 92,
            liftCount: 1,
            pauseCount: 0,
            icarSpiralScore1to4: 0
        ),
        inputMode: "Pencil"
    )
}
