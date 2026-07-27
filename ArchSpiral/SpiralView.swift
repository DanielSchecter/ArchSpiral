//
//  SpiralView.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 2/2/26.
//

import SwiftUI

struct SpiralView: View {
    var turns: CGFloat = 3
    var a: CGFloat = 8
    var margin: CGFloat = 24

    // computed b that fits the view (depends on size, so computed inside body)
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxR = min(size.width, size.height) / 2 - margin
            let thetaMax = 2 * CGFloat.pi * turns
            let b = max(1, (maxR - a) / thetaMax)

            Canvas { context, _ in
                var path = Path()
                let step: CGFloat = 0.02
                var theta: CGFloat = 0
                var started = false

                while theta <= thetaMax {
                    let r = a + b * theta
                    let x = center.x + r * cos(theta)
                    let y = center.y + r * sin(theta)
                    let p = CGPoint(x: x, y: y)

                    if !started {
                        path.move(to: p)
                        started = true
                    } else {
                        path.addLine(to: p)
                    }

                    theta += step
                }

                context.stroke(path, with: .color(.gray.opacity(0.6)), lineWidth: 8)
            }
        }
        .allowsHitTesting(false)
    }
}
