import FirmamentCore
import RealityKit
import SwiftUI

/// Material construction and the grid-line overlay for `SkyDomeScene`.
extension SkyDomeScene {
    static let edgeMaterial = UnlitMaterial(color: .black)

    static let lineMaterial: UnlitMaterial = {
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.7))
        material.faceCulling = .none
        return material
    }()

    /// Applies the precomputed line segments — in practice tube mode's distant
    /// bore sketch; the other modes carry no lines.
    func applyLines(_ frame: SkyFrame) {
        linesEntity.removeFromParent()

        if let data = frame.standardLineData, let mesh = LatticeLineMesh.resource(from: data) {
            linesEntity.model = ModelComponent(mesh: mesh, materials: [Self.lineMaterial])
            skyAnchor.addChild(linesEntity)
        }
    }

    func materials(for style: NodeStyle) -> [UnlitMaterial] {
        if let cached = materialCache[style] { return cached }

        let colors: [Color.Resolved]
        if style.isOnEclipticPlane {
            colors = Array(repeating: Color.Resolved(colorSpace: .sRGBLinear, red: 1, green: 1, blue: 1), count: 6)
        } else {
            let factor = SkyRenderer.minBrightness
                + (1 - SkyRenderer.minBrightness)
                * Double(style.brightnessLevel) / Double(SkyRenderer.brightnessLevels - 1)
            colors = appliedFaceColors.map { dimmed($0, by: Float(factor)) }
        }

        let materials = colors.map { resolved -> UnlitMaterial in
            var material = UnlitMaterial(color: UIColor(Color(resolved)))
            if style.isGhost {
                material.blending = .transparent(opacity: .init(floatLiteral: SkyRenderer.ghostOpacity))
            }
            return material
        }
        materialCache[style] = materials
        return materials
    }

    func rebuildMaterialsIfNeeded(faceColors: [Color.Resolved]) {
        guard faceColors != appliedFaceColors else { return }
        appliedFaceColors = faceColors
        materialCache.removeAll()

        for (node, entity) in entities {
            guard let style = nodeStyles[node] else { continue }
            entity.model?.materials = materials(for: style)
        }
    }

    private func dimmed(_ color: Color.Resolved, by factor: Float) -> Color.Resolved {
        Color.Resolved(
            colorSpace: .sRGBLinear,
            red: color.linearRed * factor,
            green: color.linearGreen * factor,
            blue: color.linearBlue * factor
        )
    }
}
