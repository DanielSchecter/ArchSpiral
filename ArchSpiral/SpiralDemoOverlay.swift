//
//  SpiralDemoOverlay.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 3/17/26.
//
import SwiftUI

struct SpiralDemoOverlay: View {
    var turns: CGFloat = 3
    var a: CGFloat = 8
    var margin: CGFloat = 24
    var progress: CGFloat   // 0...1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) / 2 - margin
            let thetaMax = 2 * CGFloat.pi * turns
            let b = max(1, (maxR - a) / thetaMax)

            let clampedProgress = max(0, min(1, progress))
            let currentTheta = thetaMax * clampedProgress

            Canvas { context, _ in
                var trail = Path()
                let step: CGFloat = 0.02
                var theta: CGFloat = 0
                var started = false
                var currentPoint = CGPoint(x: center.x + a, y: center.y)

                while theta <= currentTheta {
                    let r = a + b * theta
                    let x = center.x + r * cos(theta)
                    let y = center.y + r * sin(theta)
                    let p = CGPoint(x: x, y: y)

                    currentPoint = p

                    if !started {
                        trail.move(to: p)
                        started = true
                    } else {
                        trail.addLine(to: p)
                    }

                    theta += step
                }

                context.stroke(
                    trail,
                    with: .color(.red.opacity(0.85)),
                    lineWidth: 6
                )

                let dotRect = CGRect(
                    x: currentPoint.x - 7,
                    y: currentPoint.y - 7,
                    width: 14,
                    height: 14
                )

                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(.red)
                )
            }
        }
        .allowsHitTesting(false)
    }
}
