//  SessionSaver.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 2/2/26.
//

import Foundation
import PencilKit
import UIKit

enum SessionSaver {

    /// Creates TEMP files for sharing (Notes / Files / AirDrop).
    /// Caller should delete them after the share completes.
    static func saveSession(
        metricsText: String,
        drawing: PKDrawing,
        scale: CGFloat = 1.0
    ) throws -> [URL] {

        let fm = FileManager.default

        // TEMP directory → does NOT persist / no app bloat
        let tmp = fm.temporaryDirectory

        let stamp = timestamp()
        let base = "ArchSpiral_\(stamp)"

        var urls: [URL] = []

        // 1) Save metrics text
        let txtURL = tmp.appendingPathComponent("\(base).txt")
        let txtData = metricsText.data(using: .utf8) ?? Data()
        try txtData.write(to: txtURL, options: .atomic)
        urls.append(txtURL)

        // 2) Save drawing image (cropped to drawing bounds)
        let bounds: CGRect
        if drawing.bounds.isEmpty {
            bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        } else {
            bounds = drawing.bounds.insetBy(dx: -20, dy: -20)
        }

        let renderScale = max(scale, 1.0)
        let img = drawing.image(from: bounds, scale: renderScale)

        let pngURL = tmp.appendingPathComponent("\(base).png")
        if let png = img.pngData() {
            try png.write(to: pngURL, options: .atomic)
            urls.append(pngURL)
        }

        // 3) Save raw drawing data (reloadable later if needed)
        let drawingURL = tmp.appendingPathComponent("\(base).drawing")
        try drawing.dataRepresentation().write(to: drawingURL, options: .atomic)
        urls.append(drawingURL)

        return urls
    }

    /// Call AFTER share completes
    static func cleanup(_ urls: [URL]) {
        let fm = FileManager.default
        for u in urls {
            try? fm.removeItem(at: u)
        }
    }

    // MARK: - Helpers

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }
}
