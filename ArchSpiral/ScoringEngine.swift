//
//  ScoringEngine.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 2/2/26.
//

import Foundation
import PencilKit
import CoreGraphics

enum ScoringEngine {

    struct SamplePoint {
        let x: Double
        let y: Double
        let t: Double
    }

    struct SpiralTracePoint {
        let point: CGPoint
        let theta: Double
        let r: Double
    }

    struct PolarPoint {
        let r: Double
        let theta: Double
    }

    /// Scores the trace against the same spiral template:
    /// r = a + b*theta, theta in [0, thetaMax]
    static func score(
        drawing: PKDrawing,
        canvasSize: CGSize,
        center: CGPoint,
        a: CGFloat,
        b: CGFloat,
        turns: CGFloat,
        margin: CGFloat,
        toleranceFractionOfMinSide: Double = 0.04,
        pauseGapSeconds: Double = 0.35
    ) -> TraceMetrics {

        // 1) Extract the original PencilKit samples
        let samples = extractSamples(from: drawing)

        // Each stroke beyond the first implies a lift
        let liftCount = max(0, drawing.strokes.count - 1)

        /*
         Existing morphology score.

         The established logic for scores 2, 3, and 4 remains
         completely unchanged inside computeICARScore(...).
         */
        let existingMorphologyScore = computeICARScore(
            drawing: drawing,
            samples: samples,
            center: center
        )

        let tolerance =
            Double(min(canvasSize.width, canvasSize.height))
            * toleranceFractionOfMinSide

        // Not enough points for meaningful quantitative scoring
        guard samples.count >= 20 else {
            return TraceMetrics(
                date: Date(),
                percentWithinTolerance: 0,
                rmsePixels: Double.infinity,
                tolerancePixels: tolerance,
                durationSeconds: 0,
                avgSpeedPxPerSec: 0,
                shakinessScore0to100: 0,
                liftCount: liftCount,
                pauseCount: 0,
                icarSpiralScore1to4: existingMorphologyScore
            )
        }

        // 2) Duration — unchanged
        let duration = max(
            0.001,
            samples.last!.t - samples.first!.t
        )

        // 3) Average speed — unchanged
        let totalDistance = pathLength(samples)
        let averageSpeed = totalDistance / duration

        // 4) Pauses — unchanged
        var pauseCount = 0

        for index in 1..<samples.count {
            let timeGap =
                samples[index].t
                - samples[index - 1].t

            if timeGap >= pauseGapSeconds {
                pauseCount += 1
            }
        }

        /*
         5) Accuracy and RMSE

         Compare both directions:
         - traced path to the exact curve r = a + b*theta
         - exact curve back to the traced path

         Resample uniformly by path distance first so quickly drawn
         errors count as much as slowly drawn portions of equal length.
         */
        let accuracyPoints =
            uniformlyResampledAccuracyPoints(
                from: drawing,
                spacingPixels: 3.0
            )

        let traceToTemplateDistances =
            nearestDistancesToArchimedeanSpiral(
                points: accuracyPoints,
                center: center,
                a: a,
                b: b,
                turns: turns
            )

        let referencePoints =
            uniformlySampledArchimedeanSpiralPoints(
                center: center,
                a: a,
                b: b,
                turns: turns,
                spacingPixels: 3.0
            )

        let templateToTraceDistances =
            nearestDistancesToTrace(
                points: referencePoints,
                tracePolylines: drawingPolylines(
                    from: drawing
                )
            )

        let percentWithinTolerance: Double
        let rmse: Double

        if traceToTemplateDistances.isEmpty
            || templateToTraceDistances.isEmpty {

            percentWithinTolerance = 0
            rmse = Double.infinity
        } else {
            let traceAdherenceAccuracy =
                accuracyFraction(
                    distances: traceToTemplateDistances,
                    tolerancePixels: tolerance
                )

            let templateCoverageAccuracy =
                accuracyFraction(
                    distances: templateToTraceDistances,
                    tolerancePixels: tolerance
                )

            percentWithinTolerance = min(
                traceAdherenceAccuracy,
                templateCoverageAccuracy
            )

            let traceMeanSquaredDistance =
                traceToTemplateDistances
                    .map { $0 * $0 }
                    .reduce(0, +)
                / Double(traceToTemplateDistances.count)

            let templateMeanSquaredDistance =
                templateToTraceDistances
                    .map { $0 * $0 }
                    .reduce(0, +)
                / Double(templateToTraceDistances.count)

            rmse = sqrt(
                0.5 * (
                    traceMeanSquaredDistance
                    + templateMeanSquaredDistance
                )
            )
        }

        /*
         6) Steadiness

         Preserve the original radial-error calculation solely for
         the existing steadiness mechanism. Its underlying calculation
         is not changed.
         */
        let radialErrors = radialErrorsForSteadiness(
            samples: samples,
            center: center,
            a: a,
            b: b,
            turns: turns
        )

        let steadiness =
            shakinessScore0to100(
                fromRadialErrors: radialErrors
            )

        /*
         7) Digital score 0

         Only an existing score 1 can become score 0.

         Scores 2, 3, and 4 are returned unchanged.
         */
        let finalDigitalScore =
            addNearPerfectScoreZero(
                existingMorphologyScore:
                    existingMorphologyScore,
                percentWithinTolerance:
                    percentWithinTolerance,
                rmsePixels:
                    rmse,
                tolerancePixels:
                    tolerance
            )

        return TraceMetrics(
            date: Date(),
            percentWithinTolerance:
                percentWithinTolerance,
            rmsePixels: rmse,
            tolerancePixels: tolerance,
            durationSeconds: duration,
            avgSpeedPxPerSec: averageSpeed,
            shakinessScore0to100: steadiness,
            liftCount: liftCount,
            pauseCount: pauseCount,
            icarSpiralScore1to4: finalDigitalScore
        )
    }

    // MARK: - Exact Archimedean-spiral accuracy

    /// Combines path coverage inside the tolerance band with a smooth
    /// cap based on the 95th-percentile error. This prevents a severe
    /// excursion from appearing highly accurate merely because it is
    /// shorter than the otherwise close portion of the trace.
    static func accuracyFraction(
        distances: [Double],
        tolerancePixels: Double
    ) -> Double {

        guard !distances.isEmpty,
              tolerancePixels.isFinite,
              tolerancePixels > 0 else {
            return 0
        }

        let finiteDistances = distances.filter {
            $0.isFinite && $0 >= 0
        }

        guard !finiteDistances.isEmpty else {
            return 0
        }

        let withinToleranceCount =
            finiteDistances.filter {
                $0 <= tolerancePixels
            }.count

        let withinToleranceFraction =
            Double(withinToleranceCount)
            / Double(finiteDistances.count)

        let sortedDistances = finiteDistances.sorted()
        let percentileIndex = min(
            sortedDistances.count - 1,
            max(
                0,
                Int(
                    ceil(
                        0.95
                        * Double(sortedDistances.count)
                    )
                ) - 1
            )
        )

        let distanceAt95thPercentile =
            sortedDistances[percentileIndex]

        let normalizedSevereError =
            distanceAt95thPercentile
            / (2.0 * tolerancePixels)

        let severeErrorAccuracyCap = exp(
            -0.5
            * normalizedSevereError
            * normalizedSevereError
        )

        return min(
            withinToleranceFraction,
            severeErrorAccuracyCap
        )
    }

    /// Finds each sample's minimum distance to r = a + b*theta.
    /// Stationary points of squared Euclidean distance are bracketed
    /// across the full theta domain, then refined by bisection.
    static func nearestDistancesToArchimedeanSpiral(
        points: [CGPoint],
        center: CGPoint,
        a: CGFloat,
        b: CGFloat,
        turns: CGFloat,
        angularScanStep: Double = 0.05
    ) -> [Double] {

        let thetaMaximum =
            2.0 * Double.pi * Double(turns)

        guard thetaMaximum.isFinite,
              thetaMaximum > 0 else {
            return []
        }

        let centerX = Double(center.x)
        let centerY = Double(center.y)
        let spiralA = Double(a)
        let spiralB = Double(b)

        return points.compactMap { point in
            guard point.x.isFinite,
                  point.y.isFinite else {
                return nil
            }

            let minimumSquaredDistance =
                minimumSquaredDistanceToArchimedeanSpiral(
                    pointX: Double(point.x) - centerX,
                    pointY: Double(point.y) - centerY,
                    a: spiralA,
                    b: spiralB,
                    thetaMaximum: thetaMaximum,
                    angularScanStep: angularScanStep
                )

            guard minimumSquaredDistance.isFinite else {
                return nil
            }

            return sqrt(max(0, minimumSquaredDistance))
        }
    }

    /// Produces equal-distance samples without connecting separate
    /// PencilKit strokes across a lift.
    static func uniformlyResampledAccuracyPoints(
        from drawing: PKDrawing,
        spacingPixels: Double
    ) -> [CGPoint] {

        var output: [CGPoint] = []

        for stroke in drawing.strokes {
            let path = stroke.path

            guard path.count > 0 else {
                continue
            }

            var strokePoints: [CGPoint] = []
            strokePoints.reserveCapacity(path.count)

            for index in 0..<path.count {
                strokePoints.append(path[index].location)
            }

            output.append(
                contentsOf: uniformlyResampledPoints(
                    strokePoints,
                    spacingPixels: spacingPixels
                )
            )
        }

        return output
    }

    static func drawingPolylines(
        from drawing: PKDrawing
    ) -> [[CGPoint]] {

        drawing.strokes.compactMap { stroke in
            let path = stroke.path

            guard path.count > 0 else {
                return nil
            }

            return (0..<path.count).map {
                path[$0].location
            }
        }
    }

    /// Samples points lying exactly on r = a + b*theta at uniform
    /// arc-length intervals. Arc length is inverted numerically.
    static func uniformlySampledArchimedeanSpiralPoints(
        center: CGPoint,
        a: CGFloat,
        b: CGFloat,
        turns: CGFloat,
        spacingPixels: Double
    ) -> [CGPoint] {

        let spiralA = Double(a)
        let spiralB = Double(b)
        let thetaMaximum =
            2.0 * Double.pi * Double(turns)

        guard thetaMaximum.isFinite,
              thetaMaximum > 0 else {
            return []
        }

        let totalArcLength =
            archimedeanArcLength(
                theta: thetaMaximum,
                a: spiralA,
                b: spiralB
            )

        guard totalArcLength.isFinite,
              totalArcLength > 0 else {
            return []
        }

        let spacing = max(0.5, spacingPixels)
        var output = [
            archimedeanPoint(
                center: center,
                theta: 0,
                a: spiralA,
                b: spiralB
            )
        ]

        var previousTheta = 0.0
        var targetArcLength = spacing

        while targetArcLength < totalArcLength {
            var lowerTheta = previousTheta
            var upperTheta = thetaMaximum

            for _ in 0..<44 {
                let middleTheta =
                    0.5 * (lowerTheta + upperTheta)

                let middleArcLength =
                    archimedeanArcLength(
                        theta: middleTheta,
                        a: spiralA,
                        b: spiralB
                    )

                if middleArcLength < targetArcLength {
                    lowerTheta = middleTheta
                } else {
                    upperTheta = middleTheta
                }
            }

            let theta = 0.5 * (lowerTheta + upperTheta)

            output.append(
                archimedeanPoint(
                    center: center,
                    theta: theta,
                    a: spiralA,
                    b: spiralB
                )
            )

            previousTheta = theta
            targetArcLength += spacing
        }

        output.append(
            archimedeanPoint(
                center: center,
                theta: thetaMaximum,
                a: spiralA,
                b: spiralB
            )
        )

        return output
    }

    static func archimedeanArcLength(
        theta: Double,
        a: Double,
        b: Double
    ) -> Double {

        guard abs(b) > 1e-9 else {
            return abs(a * theta)
        }

        func primitive(radius: Double) -> Double {
            let bSquared = b * b

            return 0.5 * (
                radius
                * sqrt(radius * radius + bSquared)
                + bSquared * asinh(radius / abs(b))
            )
        }

        let startRadius = a
        let endRadius = a + b * theta

        return abs(
            (primitive(radius: endRadius)
                - primitive(radius: startRadius))
            / b
        )
    }

    static func archimedeanPoint(
        center: CGPoint,
        theta: Double,
        a: Double,
        b: Double
    ) -> CGPoint {

        let radius = a + b * theta

        return CGPoint(
            x: Double(center.x) + radius * cos(theta),
            y: Double(center.y) + radius * sin(theta)
        )
    }

    static func nearestDistancesToTrace(
        points: [CGPoint],
        tracePolylines: [[CGPoint]]
    ) -> [Double] {

        guard tracePolylines.contains(where: { !$0.isEmpty }) else {
            return []
        }

        return points.compactMap { point in
            var minimumDistance =
                Double.greatestFiniteMagnitude

            for polyline in tracePolylines {
                if polyline.count == 1,
                   let onlyPoint = polyline.first {

                    let dx = Double(point.x - onlyPoint.x)
                    let dy = Double(point.y - onlyPoint.y)

                    minimumDistance = min(
                        minimumDistance,
                        sqrt(dx * dx + dy * dy)
                    )
                } else if polyline.count >= 2 {
                    for index in 0..<(polyline.count - 1) {
                        minimumDistance = min(
                            minimumDistance,
                            pointToSegmentDistance(
                                point,
                                polyline[index],
                                polyline[index + 1]
                            )
                        )
                    }
                }
            }

            return minimumDistance.isFinite
                ? minimumDistance
                : nil
        }
    }

    static func uniformlyResampledPoints(
        _ points: [CGPoint],
        spacingPixels: Double
    ) -> [CGPoint] {

        guard let firstPoint = points.first else {
            return []
        }

        let spacing = max(0.5, spacingPixels)
        var output = [firstPoint]
        var previousInputPoint = firstPoint
        var distanceSinceOutput = 0.0

        for inputPoint in points.dropFirst() {
            var segmentStart = previousInputPoint
            var segmentX = Double(inputPoint.x - segmentStart.x)
            var segmentY = Double(inputPoint.y - segmentStart.y)
            var segmentLength = sqrt(
                segmentX * segmentX
                + segmentY * segmentY
            )

            while segmentLength > 1e-9,
                  distanceSinceOutput + segmentLength >= spacing {

                let distanceNeeded =
                    spacing - distanceSinceOutput

                let fraction = distanceNeeded / segmentLength
                let resampledPoint = CGPoint(
                    x: Double(segmentStart.x)
                        + fraction * segmentX,
                    y: Double(segmentStart.y)
                        + fraction * segmentY
                )

                output.append(resampledPoint)
                segmentStart = resampledPoint
                distanceSinceOutput = 0

                segmentX = Double(inputPoint.x - segmentStart.x)
                segmentY = Double(inputPoint.y - segmentStart.y)
                segmentLength = sqrt(
                    segmentX * segmentX
                    + segmentY * segmentY
                )
            }

            distanceSinceOutput += segmentLength
            previousInputPoint = inputPoint
        }

        if let lastPoint = points.last,
           let lastOutputPoint = output.last {

            let dx = Double(lastPoint.x - lastOutputPoint.x)
            let dy = Double(lastPoint.y - lastOutputPoint.y)

            if sqrt(dx * dx + dy * dy) >= spacing * 0.25 {
                output.append(lastPoint)
            }
        }

        return output
    }

    static func minimumSquaredDistanceToArchimedeanSpiral(
        pointX: Double,
        pointY: Double,
        a: Double,
        b: Double,
        thetaMaximum: Double,
        angularScanStep: Double
    ) -> Double {

        let scanStep = max(
            0.01,
            min(0.10, abs(angularScanStep))
        )

        var bestDistanceSquared = min(
            archimedeanDistanceSquared(
                pointX: pointX,
                pointY: pointY,
                theta: 0,
                a: a,
                b: b
            ),
            archimedeanDistanceSquared(
                pointX: pointX,
                pointY: pointY,
                theta: thetaMaximum,
                a: a,
                b: b
            )
        )

        var leftTheta = 0.0
        var leftDerivative =
            archimedeanDistanceDerivativeHalf(
                pointX: pointX,
                pointY: pointY,
                theta: leftTheta,
                a: a,
                b: b
            )

        while leftTheta < thetaMaximum {
            let rightTheta = min(
                thetaMaximum,
                leftTheta + scanStep
            )

            let rightDerivative =
                archimedeanDistanceDerivativeHalf(
                    pointX: pointX,
                    pointY: pointY,
                    theta: rightTheta,
                    a: a,
                    b: b
                )

            if leftDerivative == 0 {
                bestDistanceSquared = min(
                    bestDistanceSquared,
                    archimedeanDistanceSquared(
                        pointX: pointX,
                        pointY: pointY,
                        theta: leftTheta,
                        a: a,
                        b: b
                    )
                )
            }

            let derivativeChangesSign =
                (leftDerivative < 0 && rightDerivative > 0)
                || (leftDerivative > 0 && rightDerivative < 0)

            if derivativeChangesSign {
                let stationaryTheta =
                    refineArchimedeanStationaryTheta(
                        pointX: pointX,
                        pointY: pointY,
                        a: a,
                        b: b,
                        lowerTheta: leftTheta,
                        upperTheta: rightTheta,
                        lowerDerivative: leftDerivative
                    )

                bestDistanceSquared = min(
                    bestDistanceSquared,
                    archimedeanDistanceSquared(
                        pointX: pointX,
                        pointY: pointY,
                        theta: stationaryTheta,
                        a: a,
                        b: b
                    )
                )
            }

            leftTheta = rightTheta
            leftDerivative = rightDerivative
        }

        return bestDistanceSquared
    }

    static func refineArchimedeanStationaryTheta(
        pointX: Double,
        pointY: Double,
        a: Double,
        b: Double,
        lowerTheta: Double,
        upperTheta: Double,
        lowerDerivative: Double
    ) -> Double {

        var lower = lowerTheta
        var upper = upperTheta
        var derivativeAtLower = lowerDerivative

        for _ in 0..<48 {
            let middle = 0.5 * (lower + upper)
            let derivativeAtMiddle =
                archimedeanDistanceDerivativeHalf(
                    pointX: pointX,
                    pointY: pointY,
                    theta: middle,
                    a: a,
                    b: b
                )

            if abs(derivativeAtMiddle) < 1e-10 {
                return middle
            }

            let rootIsInLowerHalf =
                (derivativeAtLower < 0
                    && derivativeAtMiddle > 0)
                || (derivativeAtLower > 0
                    && derivativeAtMiddle < 0)

            if rootIsInLowerHalf {
                upper = middle
            } else {
                lower = middle
                derivativeAtLower = derivativeAtMiddle
            }
        }

        return 0.5 * (lower + upper)
    }

    static func archimedeanDistanceSquared(
        pointX: Double,
        pointY: Double,
        theta: Double,
        a: Double,
        b: Double
    ) -> Double {

        let radius = a + b * theta
        let differenceX = radius * cos(theta) - pointX
        let differenceY = radius * sin(theta) - pointY

        return differenceX * differenceX
            + differenceY * differenceY
    }

    /// One half of d/dtheta for squared Euclidean distance.
    static func archimedeanDistanceDerivativeHalf(
        pointX: Double,
        pointY: Double,
        theta: Double,
        a: Double,
        b: Double
    ) -> Double {

        let radius = a + b * theta
        let cosine = cos(theta)
        let sine = sin(theta)

        let spiralX = radius * cosine
        let spiralY = radius * sine

        let tangentX = b * cosine - radius * sine
        let tangentY = b * sine + radius * cosine

        return (spiralX - pointX) * tangentX
            + (spiralY - pointY) * tangentY
    }

    // MARK: - Existing steadiness input

    /// Recreates the original radial errors used by the existing
    /// steadiness calculation. This preserves that mechanism.
    static func radialErrorsForSteadiness(
        samples: [SamplePoint],
        center: CGPoint,
        a: CGFloat,
        b: CGFloat,
        turns: CGFloat
    ) -> [Double] {

        let polar = toPolar(
            samples,
            center: center
        )

        let unwrappedTheta =
            unwrapTheta(
                polar.map { $0.theta }
            )

        let radii = polar.map { $0.r }

        let startingTheta =
            unwrappedTheta.first ?? 0

        var normalizedTheta =
            unwrappedTheta.map {
                $0 - startingTheta
            }

        if let lastTheta = normalizedTheta.last,
           lastTheta < 0 {

            normalizedTheta =
                normalizedTheta.map { -$0 }
        }

        let thetaMaximum =
            2.0 * Double.pi * Double(turns)

        var errors: [Double] = []
        errors.reserveCapacity(
            normalizedTheta.count
        )

        for index in 0..<normalizedTheta.count {
            let theta = normalizedTheta[index]

            guard theta >= 0,
                  theta <= thetaMaximum else {
                continue
            }

            let expectedRadius =
                Double(a) + Double(b) * theta

            errors.append(
                radii[index] - expectedRadius
            )
        }

        return errors
    }

    // MARK: - Digital score 0

    /// Subdivides only the existing score-1 category.
    ///
    /// 0 = near-perfect tracing of the reference spiral.
    /// 1 = does not meet criteria for 2, 3, or 4, but is
    ///     less exact than a score-0 tracing.
    ///
    /// Existing scores 2, 3, and 4 are returned unchanged.
    static func addNearPerfectScoreZero(
        existingMorphologyScore: Int,
        percentWithinTolerance: Double,
        rmsePixels: Double,
        tolerancePixels: Double,
        nearPerfectAccuracyThreshold: Double = 0.75,
        nearPerfectRMSEFractionOfTolerance: Double = 0.90
    ) -> Int {

        // Never modify scores 2, 3, or 4
        guard existingMorphologyScore == 1 else {
            return existingMorphologyScore
        }

        guard percentWithinTolerance.isFinite,
              rmsePixels.isFinite,
              tolerancePixels.isFinite,
              tolerancePixels > 0 else {
            return 1
        }

        let accuracyIsNearPerfect =
            percentWithinTolerance
            >= nearPerfectAccuracyThreshold

        let rmseIsNearPerfect =
            rmsePixels
            <= tolerancePixels
                * nearPerfectRMSEFractionOfTolerance

        return accuracyIsNearPerfect
            && rmseIsNearPerfect
            ? 0
            : 1
    }

    // MARK: - Extraction (PencilKit)

    static func extractSamples(
        from drawing: PKDrawing
    ) -> [SamplePoint] {

        var out: [SamplePoint] = []
        out.reserveCapacity(2000)

        var tBase: Double = 0

        for stroke in drawing.strokes {
            let path = stroke.path

            guard path.count > 0 else {
                continue
            }

            for i in 0..<path.count {
                let p = path[i]

                out.append(
                    SamplePoint(
                        x: Double(p.location.x),
                        y: Double(p.location.y),
                        t: tBase + p.timeOffset
                    )
                )
            }

            if let last = out.last {
                tBase = last.t
            }
        }

        return out
    }

    /// Estimates the typical stroke width in pixels.
    static func estimatedStrokeWidthPx(
        from drawing: PKDrawing
    ) -> Double {

        var widths: [Double] = []
        widths.reserveCapacity(256)

        for stroke in drawing.strokes {
            let path = stroke.path

            guard path.count > 0 else {
                continue
            }

            let stride = max(
                1,
                path.count / 80
            )

            var i = 0

            while i < path.count {
                let strokePoint = path[i]

                let width = Double(
                    (
                        strokePoint.size.width
                        + strokePoint.size.height
                    ) * 0.5
                )

                if width.isFinite,
                   width > 0 {
                    widths.append(width)
                }

                i += stride
            }
        }

        guard !widths.isEmpty else {
            return 6.0
        }

        widths.sort()

        let middle = widths.count / 2

        if widths.count % 2 == 1 {
            return widths[middle]
        }

        return 0.5 * (
            widths[middle - 1]
            + widths[middle]
        )
    }

    // MARK: - Geometry helpers

    static func pathLength(
        _ samples: [SamplePoint]
    ) -> Double {

        guard samples.count >= 2 else {
            return 0
        }

        var distance = 0.0

        for i in 1..<samples.count {
            let dx =
                samples[i].x
                - samples[i - 1].x

            let dy =
                samples[i].y
                - samples[i - 1].y

            distance += sqrt(
                dx * dx + dy * dy
            )
        }

        return distance
    }

    static func toPolar(
        _ samples: [SamplePoint],
        center: CGPoint
    ) -> [PolarPoint] {

        let centerX = Double(center.x)
        let centerY = Double(center.y)

        return samples.map { sample in
            let dx = sample.x - centerX
            let dy = sample.y - centerY

            return PolarPoint(
                r: sqrt(dx * dx + dy * dy),
                theta: atan2(dy, dx)
            )
        }
    }

    static func unwrapTheta(
        _ theta: [Double]
    ) -> [Double] {

        guard !theta.isEmpty else {
            return []
        }

        var output =
            [Double](
                repeating: 0,
                count: theta.count
            )

        output[0] = theta[0]

        var offset = 0.0

        for i in 1..<theta.count {
            let delta =
                theta[i] - theta[i - 1]

            if delta > Double.pi {
                offset -= 2.0 * Double.pi
            } else if delta < -Double.pi {
                offset += 2.0 * Double.pi
            }

            output[i] =
                theta[i] + offset
        }

        return output
    }

    // MARK: - Steadiness calculation

    /// Original calculation is unchanged.
    /// Higher values indicate smoother or steadier tracing.
    static func shakinessScore0to100(
        fromRadialErrors errors: [Double]
    ) -> Double {

        guard errors.count >= 30 else {
            return 0
        }

        let window = 15

        var movingAverage =
            [Double](
                repeating: 0,
                count: errors.count
            )

        var sum = 0.0

        for i in 0..<errors.count {
            sum += errors[i]

            if i >= window {
                sum -= errors[i - window]
            }

            let denominator =
                Double(min(i + 1, window))

            movingAverage[i] =
                sum / denominator
        }

        var highFrequencyError: [Double] = []
        highFrequencyError.reserveCapacity(
            errors.count
        )

        for i in 0..<errors.count {
            highFrequencyError.append(
                errors[i]
                - movingAverage[i]
            )
        }

        let rms = sqrt(
            highFrequencyError
                .map { $0 * $0 }
                .reduce(0, +)
            / Double(highFrequencyError.count)
        )

        let lowThreshold = 3.0
        let highThreshold = 25.0

        let normalized =
            (rms - lowThreshold)
            / (highThreshold - lowThreshold)

        return 100.0 * (
            1.0
            - min(
                1.0,
                max(0.0, normalized)
            )
        )
    }

    // MARK: - ICAR Spiral Scoring

    /*
     Existing morphology mechanism is unchanged.

     1 = spiral with no self-touch and no crossing
     2 = self-touch or overlap across different loops
     3 = proper self-crossing across different loops
     4 = does not look like a spiral

     Score 0 is not assigned here. It is considered only
     after the existing morphology score has been calculated.
     */
    static func computeICARScore(
        drawing: PKDrawing,
        samples: [SamplePoint],
        center: CGPoint
    ) -> Int {

        if samples.count < 50 {
            return 4
        }

        // Require at least approximately two turns
        let polar = toPolar(
            samples,
            center: center
        )

        let thetaUnwrapped = unwrapTheta(
            polar.map { $0.theta }
        )

        let thetaStart =
            thetaUnwrapped.first ?? 0

        var theta = thetaUnwrapped.map {
            $0 - thetaStart
        }

        if let last = theta.last,
           last < 0 {
            theta = theta.map { -$0 }
        }

        let thetaSpan =
            (theta.max() ?? 0)
            - (theta.min() ?? 0)

        let turnsCovered =
            thetaSpan
            / (2.0 * Double.pi)

        if turnsCovered < 2.0 {
            return 4
        }

        let trace = downsampleTracePoints(
            samples: samples,
            center: center,
            minStepPx: 3.0,
            maxPoints: 1200
        )

        if trace.count < 30 {
            return 4
        }

        let strokeWidth =
            estimatedStrokeWidthPx(
                from: drawing
            )

        // Require interaction across clearly different loops
        let minimumLoopThetaSeparation =
            0.75 * 2.0 * Double.pi

        // Require a visible crossing angle
        let minimumCrossingAngleDegrees =
            28.0

        // Existing score 3 logic
        if hasSelfCrossingAcrossLoops(
            trace: trace,
            minThetaSeparation:
                minimumLoopThetaSeparation,
            minCrossAngleDegrees:
                minimumCrossingAngleDegrees
        ) {
            return 3
        }

        // Existing score 2 logic
        let touchThreshold = max(
            4.0,
            min(
                12.0,
                (strokeWidth * 1.15) + 1.0
            )
        )

        if hasSelfTouchAcrossLoops(
            trace: trace,
            touchThresholdPx: touchThreshold,
            minThetaSeparation:
                minimumLoopThetaSeparation
        ) {
            return 2
        }

        // Existing best morphology category
        return 1
    }

    static func downsampleTracePoints(
        samples: [SamplePoint],
        center: CGPoint,
        minStepPx: Double,
        maxPoints: Int
    ) -> [SpiralTracePoint] {

        let polar = toPolar(
            samples,
            center: center
        )

        let thetaUnwrappedRaw =
            unwrapTheta(
                polar.map { $0.theta }
            )

        let thetaStart =
            thetaUnwrappedRaw.first ?? 0

        var theta =
            thetaUnwrappedRaw.map {
                $0 - thetaStart
            }

        if let last = theta.last,
           last < 0 {
            theta = theta.map { -$0 }
        }

        var output: [SpiralTracePoint] = []

        output.reserveCapacity(
            min(maxPoints, samples.count)
        )

        var lastPoint: CGPoint?

        for i in 0..<samples.count {
            let point = CGPoint(
                x: samples[i].x,
                y: samples[i].y
            )

            if let previousPoint = lastPoint {
                let dx =
                    Double(
                        point.x
                        - previousPoint.x
                    )

                let dy =
                    Double(
                        point.y
                        - previousPoint.y
                    )

                if sqrt(dx * dx + dy * dy)
                    < minStepPx {
                    continue
                }
            }

            output.append(
                SpiralTracePoint(
                    point: point,
                    theta: theta[i],
                    r: polar[i].r
                )
            )

            lastPoint = point

            if output.count >= maxPoints {
                break
            }
        }

        return output
    }

    // MARK: - Existing score 3 logic

    static func hasSelfCrossingAcrossLoops(
        trace: [SpiralTracePoint],
        minThetaSeparation: Double,
        minCrossAngleDegrees: Double
    ) -> Bool {

        guard trace.count >= 4 else {
            return false
        }

        for i in 0..<(trace.count - 1) {
            let firstA = trace[i]
            let secondA = trace[i + 1]

            if segmentLength(
                firstA.point,
                secondA.point
            ) < 4.0 {
                continue
            }

            if i + 2 >= trace.count - 1 {
                continue
            }

            for j in (i + 2)..<(trace.count - 1) {
                if j == i || j == i + 1 {
                    continue
                }

                let firstB = trace[j]
                let secondB = trace[j + 1]

                if segmentLength(
                    firstB.point,
                    secondB.point
                ) < 4.0 {
                    continue
                }

                let thetaMiddleA =
                    0.5 * (
                        firstA.theta
                        + secondA.theta
                    )

                let thetaMiddleB =
                    0.5 * (
                        firstB.theta
                        + secondB.theta
                    )

                if abs(
                    thetaMiddleA
                    - thetaMiddleB
                ) < minThetaSeparation {
                    continue
                }

                if !segmentsProperlyCross(
                    firstA.point,
                    secondA.point,
                    firstB.point,
                    secondB.point
                ) {
                    continue
                }

                let crossingAngle =
                    crossingAngleDegrees(
                        firstA.point,
                        secondA.point,
                        firstB.point,
                        secondB.point
                    )

                if crossingAngle
                    < minCrossAngleDegrees {
                    continue
                }

                return true
            }
        }

        return false
    }

    // MARK: - Existing score 2 logic

    static func hasSelfTouchAcrossLoops(
        trace: [SpiralTracePoint],
        touchThresholdPx: Double,
        minThetaSeparation: Double
    ) -> Bool {

        guard trace.count >= 4 else {
            return false
        }

        for i in 0..<(trace.count - 1) {
            let firstA = trace[i]
            let secondA = trace[i + 1]

            if i + 3 >= trace.count - 1 {
                continue
            }

            for j in (i + 3)..<(trace.count - 1) {
                let firstB = trace[j]
                let secondB = trace[j + 1]

                let thetaMiddleA =
                    0.5 * (
                        firstA.theta
                        + secondA.theta
                    )

                let thetaMiddleB =
                    0.5 * (
                        firstB.theta
                        + secondB.theta
                    )

                if abs(
                    thetaMiddleA
                    - thetaMiddleB
                ) < minThetaSeparation {
                    continue
                }

                // Proper crossings remain score 3
                if segmentsProperlyCross(
                    firstA.point,
                    secondA.point,
                    firstB.point,
                    secondB.point
                ) {
                    continue
                }

                // Exact contact or overlap
                if segmentsIntersectExact(
                    firstA.point,
                    secondA.point,
                    firstB.point,
                    secondB.point
                ) {
                    return true
                }

                // Near-touch
                if segmentDistance(
                    firstA.point,
                    secondA.point,
                    firstB.point,
                    secondB.point
                ) <= touchThresholdPx {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Segment helpers

    static func segmentLength(
        _ first: CGPoint,
        _ second: CGPoint
    ) -> Double {

        let dx =
            Double(second.x - first.x)

        let dy =
            Double(second.y - first.y)

        return sqrt(dx * dx + dy * dy)
    }

    static func crossingAngleDegrees(
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ q1: CGPoint,
        _ q2: CGPoint
    ) -> Double {

        let ux = Double(p2.x - p1.x)
        let uy = Double(p2.y - p1.y)
        let vx = Double(q2.x - q1.x)
        let vy = Double(q2.y - q1.y)

        let lengthU =
            sqrt(ux * ux + uy * uy)

        let lengthV =
            sqrt(vx * vx + vy * vy)

        guard lengthU > 0,
              lengthV > 0 else {
            return 0
        }

        var cosine =
            (ux * vx + uy * vy)
            / (lengthU * lengthV)

        cosine = max(
            -1.0,
            min(1.0, cosine)
        )

        return acos(abs(cosine))
            * 180.0
            / Double.pi
    }

    /// Proper crossing only.
    /// Excludes colinear overlap and endpoint touching.
    static func segmentsProperlyCross(
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ q1: CGPoint,
        _ q2: CGPoint
    ) -> Bool {

        let orientation1 =
            orientation(p1, p2, q1)

        let orientation2 =
            orientation(p1, p2, q2)

        let orientation3 =
            orientation(q1, q2, p1)

        let orientation4 =
            orientation(q1, q2, p2)

        return orientation1 != 0
            && orientation2 != 0
            && orientation3 != 0
            && orientation4 != 0
            && orientation1 != orientation2
            && orientation3 != orientation4
    }

    static func segmentDistance(
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ q1: CGPoint,
        _ q2: CGPoint
    ) -> Double {

        if segmentsIntersectExact(
            p1,
            p2,
            q1,
            q2
        ) {
            return 0
        }

        return min(
            pointToSegmentDistance(
                p1,
                q1,
                q2
            ),
            pointToSegmentDistance(
                p2,
                q1,
                q2
            ),
            pointToSegmentDistance(
                q1,
                p1,
                p2
            ),
            pointToSegmentDistance(
                q2,
                p1,
                p2
            )
        )
    }

    static func pointToSegmentDistance(
        _ point: CGPoint,
        _ segmentStart: CGPoint,
        _ segmentEnd: CGPoint
    ) -> Double {

        let pointX = Double(point.x)
        let pointY = Double(point.y)

        let startX = Double(segmentStart.x)
        let startY = Double(segmentStart.y)

        let endX = Double(segmentEnd.x)
        let endY = Double(segmentEnd.y)

        let segmentX = endX - startX
        let segmentY = endY - startY

        let pointFromStartX =
            pointX - startX

        let pointFromStartY =
            pointY - startY

        let segmentLengthSquared =
            segmentX * segmentX
            + segmentY * segmentY

        if segmentLengthSquared == 0 {
            return sqrt(
                pointFromStartX * pointFromStartX
                + pointFromStartY * pointFromStartY
            )
        }

        var position =
            (
                pointFromStartX * segmentX
                + pointFromStartY * segmentY
            )
            / segmentLengthSquared

        position = max(
            0,
            min(1, position)
        )

        let closestX =
            startX + position * segmentX

        let closestY =
            startY + position * segmentY

        let dx = pointX - closestX
        let dy = pointY - closestY

        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Exact segment intersection

    static func segmentsIntersectExact(
        _ p1: CGPoint,
        _ p2: CGPoint,
        _ q1: CGPoint,
        _ q2: CGPoint
    ) -> Bool {

        let orientation1 =
            orientation(p1, p2, q1)

        let orientation2 =
            orientation(p1, p2, q2)

        let orientation3 =
            orientation(q1, q2, p1)

        let orientation4 =
            orientation(q1, q2, p2)

        if orientation1 != orientation2,
           orientation3 != orientation4 {
            return true
        }

        if orientation1 == 0,
           onSegment(p1, q1, p2) {
            return true
        }

        if orientation2 == 0,
           onSegment(p1, q2, p2) {
            return true
        }

        if orientation3 == 0,
           onSegment(q1, p1, q2) {
            return true
        }

        if orientation4 == 0,
           onSegment(q1, p2, q2) {
            return true
        }

        return false
    }

    static func orientation(
        _ first: CGPoint,
        _ second: CGPoint,
        _ third: CGPoint
    ) -> Int {

        let value =
            (
                Double(second.y - first.y)
                * Double(third.x - second.x)
            )
            -
            (
                Double(second.x - first.x)
                * Double(third.y - second.y)
            )

        if abs(value) < 1e-9 {
            return 0
        }

        return value > 0 ? 1 : 2
    }

    static func onSegment(
        _ first: CGPoint,
        _ point: CGPoint,
        _ second: CGPoint
    ) -> Bool {

        let epsilon: CGFloat = 1e-6

        return point.x
            <= max(first.x, second.x) + epsilon
            &&
            point.x
            >= min(first.x, second.x) - epsilon
            &&
            point.y
            <= max(first.y, second.y) + epsilon
            &&
            point.y
            >= min(first.y, second.y) - epsilon
    }
}
