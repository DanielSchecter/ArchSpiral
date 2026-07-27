//
//  PencilCanvasView.swift
//  ArchSpiral
//
//  Created by Daniel Schecter on 2/2/26.
//

import SwiftUI
import PencilKit

struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var hasStartedDrawing: Bool

    var isEnabled: Bool = true
    var onFirstInput: (() -> Void)? = nil

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()

        canvas.backgroundColor = .clear
        canvas.isOpaque = false

        // Continue accepting Pencil or finger exactly as before.
        canvas.drawingPolicy = .anyInput

        canvas.tool = PKInkingTool(
            .pen,
            color: .systemBlue,
            width: 6
        )

        canvas.isScrollEnabled = false
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 1.0
        canvas.zoomScale = 1.0

        /*
         Important coordinate-alignment settings.

         PKCanvasView inherits from UIScrollView. Without these,
         iPad safe-area or toolbar insets can shift the stored
         PencilKit coordinates relative to the visible SwiftUI
         spiral template.
         */
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.contentInset = .zero
        canvas.scrollIndicatorInsets = .zero
        canvas.setContentOffset(.zero, animated: false)

        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.isUserInteractionEnabled = isEnabled

        return canvas
    }

    func updateUIView(
        _ uiView: PKCanvasView,
        context: Context
    ) {
        if uiView.drawing != drawing {
            context.coordinator.isUpdating = true
            uiView.drawing = drawing
            context.coordinator.isUpdating = false
        }

        uiView.isUserInteractionEnabled = isEnabled

        // Keep PencilKit and SwiftUI in the same coordinate space.
        uiView.contentInsetAdjustmentBehavior = .never
        uiView.contentInset = .zero

        if uiView.zoomScale != 1.0 {
            uiView.setZoomScale(1.0, animated: false)
        }

        if uiView.contentOffset != .zero {
            uiView.setContentOffset(.zero, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var isUpdating = false

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(
            _ canvasView: PKCanvasView
        ) {
            guard !isUpdating else {
                return
            }

            parent.drawing = canvasView.drawing

            if !parent.hasStartedDrawing &&
                !canvasView.drawing.strokes.isEmpty {

                parent.hasStartedDrawing = true
                parent.onFirstInput?()
            }
        }
    }
}
