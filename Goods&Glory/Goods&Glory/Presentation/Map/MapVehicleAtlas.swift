//
//  MapVehicleAtlas.swift
//  Goods&Glory
//
//  Every shape a vehicle is drawn with, baked once into a single texture page.
//
//  SpriteKit batches sprites that share a texture page into one draw call, and
//  batches nothing at all for SKShapeNode. A fleet of three hundred vehicles
//  drawn as shape nodes was around two thousand draw calls a frame; drawn from
//  this page it is a handful, whatever the fleet size.
//
//  The regions therefore all live in one image on purpose. Splitting them into
//  separate SKTextures would put each on its own page and undo the batching.
//

import SpriteKit
import UIKit

@MainActor
enum MapVehicleAtlas {
    /// Capsule footprint in world units. The rest of the map is laid out
    /// against these numbers, so they stay what they always were.
    static let bodySize = CGSize(width: 11, height: 7)
    static let bodyCornerRadius: CGFloat = 2.4
    static let ringRadius: CGFloat = 9
    static let sparkRadius: CGFloat = 2.6
    static let glowRadius: CGFloat = 6
    static let plateHeight: CGFloat = 11
    static let plateCornerRadius: CGFloat = 5.5
    /// Baked plate width. Sprites stretch it with a nine-slice, so only the
    /// straight middle grows and the corners keep their radius.
    static let plateBakedWidth: CGFloat = 24

    /// How many discrete fills the service-progress reveal is quantised to.
    /// A sub-rect per frame per vehicle would allocate for no visible gain;
    /// twenty-four steps is finer than the eye follows on a loading bar.
    private static let fillSteps = 24

    // MARK: - Regions

    private enum Region {
        static let padding: CGFloat = 2
        static let body = CGRect(x: 2, y: 2, width: 11, height: 7)
        static let outline = CGRect(x: 17, y: 2, width: 11, height: 7)
        static let ring = CGRect(x: 32, y: 2, width: 18, height: 18)
        static let spark = CGRect(x: 54, y: 2, width: 6, height: 6)
        static let glow = CGRect(x: 64, y: 2, width: 12, height: 12)
        static let plate = CGRect(x: 80, y: 2, width: 24, height: 11)
        static let size = CGSize(width: 108, height: 24)
    }

    // MARK: - Page

    /// Drawn at this multiple of world units so the capsule stays crisp when
    /// the player zooms in past 1:1.
    private static let renderScale: CGFloat = 8

    private static let page: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: Region.size, format: format)
            .image { context in
                let cg = context.cgContext

                // Everything is baked white so a sprite can tint it to any
                // accent with colorBlendFactor and still share this page.
                cg.setFillColor(UIColor.white.cgColor)
                cg.addPath(CGPath(
                    roundedRect: Region.body,
                    cornerWidth: bodyCornerRadius,
                    cornerHeight: bodyCornerRadius,
                    transform: nil
                ))
                cg.fillPath()

                cg.setStrokeColor(UIColor.white.cgColor)
                cg.setLineWidth(1)
                cg.addPath(CGPath(
                    roundedRect: Region.outline.insetBy(dx: 0.5, dy: 0.5),
                    cornerWidth: bodyCornerRadius,
                    cornerHeight: bodyCornerRadius,
                    transform: nil
                ))
                cg.strokePath()

                cg.setLineWidth(1.4)
                cg.strokeEllipse(in: Region.ring.insetBy(dx: 0.7, dy: 0.7))

                cg.fillEllipse(in: Region.spark)

                // The glow is a soft disc rather than a blur pass: a radial
                // gradient bakes in one draw and costs nothing at runtime.
                let colors = [
                    UIColor.white.withAlphaComponent(0.85).cgColor,
                    UIColor.white.withAlphaComponent(0).cgColor,
                ] as CFArray
                if let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: colors,
                    locations: [0, 1]
                ) {
                    cg.saveGState()
                    cg.addEllipse(in: Region.glow)
                    cg.clip()
                    let centre = CGPoint(x: Region.glow.midX, y: Region.glow.midY)
                    cg.drawRadialGradient(
                        gradient,
                        startCenter: centre, startRadius: 0,
                        endCenter: centre, endRadius: Region.glow.width / 2,
                        options: []
                    )
                    cg.restoreGState()
                }

                cg.setFillColor(UIColor.white.cgColor)
                cg.addPath(CGPath(
                    roundedRect: Region.plate,
                    cornerWidth: plateCornerRadius,
                    cornerHeight: plateCornerRadius,
                    transform: nil
                ))
                cg.fillPath()
            }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()

    private static func slice(_ rect: CGRect) -> SKTexture {
        SKTexture(
            rect: CGRect(
                x: rect.minX / Region.size.width,
                y: 1 - rect.maxY / Region.size.height,
                width: rect.width / Region.size.width,
                height: rect.height / Region.size.height
            ),
            in: page
        )
    }

    // MARK: - Textures

    static let body = slice(Region.body)
    static let outline = slice(Region.outline)
    static let ring = slice(Region.ring)
    static let spark = slice(Region.spark)
    static let glow = slice(Region.glow)
    static let plate = slice(Region.plate)

    /// Nine-slice insets for the plate, in the plate texture's own space, so a
    /// stretched name plate keeps its corner radius.
    static let plateCenterRect = CGRect(
        x: plateCornerRadius / plateBakedWidth,
        y: 0,
        width: 1 - 2 * plateCornerRadius / plateBakedWidth,
        height: 1
    )

    /// A left-anchored slice of the capsule, for the loading reveal. Sharing
    /// the page means the partly-filled body still batches with everything
    /// else on screen.
    private static let fills: [SKTexture] = (0...fillSteps).map { step in
        let fraction = CGFloat(step) / CGFloat(fillSteps)
        var rect = Region.body
        rect.size.width = max(0.35, Region.body.width * fraction)
        return slice(rect)
    }

    static func fill(progress: CGFloat) -> (texture: SKTexture, width: CGFloat) {
        let clamped = max(0, min(1, progress))
        let step = Int((clamped * CGFloat(fillSteps)).rounded())
        return (fills[step], max(0.35, bodySize.width * CGFloat(step) / CGFloat(fillSteps)))
    }
}
