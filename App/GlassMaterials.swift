import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

extension View {
    func canvasBackground() -> some View {
        background(
            VisualEffectBackground(material: .underWindowBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
    }

    func raisedGlass<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular, in: shape)
    }

    func raisedGlass(cornerRadius: CGFloat = DS.Radius.panel) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func webCardShadow() -> some View {
        shadow(color: DS.Shadows.cardColor, radius: DS.Shadows.cardRadius, y: DS.Shadows.cardY)
    }

    func cardEdgeHighlight(cornerRadius: CGFloat = DS.Radius.card) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(DS.Colors.edgeHighlight, lineWidth: 1)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        )
    }
}
