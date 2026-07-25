//
//  MapVehicleNode.swift
//  Goods&Glory
//
//  The pooled sprite a moving vehicle is drawn with, and how it changes shape
//  across the zoom range. Presentation only — it renders a marker value and
//  never reads game state.
//
//  Every part is a sprite off `MapVehicleAtlas`'s single page, so the whole
//  fleet batches into a couple of draw calls no matter how large it is. The
//  shape nodes this replaced could not batch, and the crop node that drew the
//  loading reveal opened an offscreen render pass per vehicle.
//
//  `apply` runs once per vehicle per simulation tick, so it writes only what
//  actually changed. Reassigning label text or rebuilding a plate path every
//  tick re-rasterises them every tick, which cost more than the drawing did.
//

import SpriteKit
import UIKit

final class MapVehicleNode: SKNode {
    private let selectionRing = SKSpriteNode(texture: MapVehicleAtlas.ring)
    private let chassis = SKNode()
    /// Base capsule. Dim while a service fill is drawn over it.
    private let body = SKSpriteNode(texture: MapVehicleAtlas.body)
    /// Loading/unloading fill that grows left → right inside the capsule.
    private let fill = SKSpriteNode(texture: MapVehicleAtlas.fill(progress: 0).texture)
    private let outline = SKSpriteNode(texture: MapVehicleAtlas.outline)
    private let plate = SKSpriteNode(texture: MapVehicleAtlas.plate)
    private let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
    /// What a vehicle becomes when the camera pulls back far enough that a
    /// truck silhouette is smaller than the ink it is drawn with: a point of
    /// light. Pulling back then reads as watching traffic move across a
    /// continent rather than losing sight of it.
    private let spark = SKSpriteNode(texture: MapVehicleAtlas.spark)
    private let sparkGlow = SKSpriteNode(texture: MapVehicleAtlas.glow)

    // Last-written state. Guards against re-doing work the tick did not change.
    private var appliedCode: String?
    private var appliedPlateWidth: CGFloat = 0
    private var appliedHeading: CGFloat = .infinity
    private var appliedAccent: UIColor?
    private var appliedOutlineColor: UIColor?
    private var appliedFillStep: CGFloat = -1
    private var appliedLabelColor: UIColor?
    private var appliedPlateY: CGFloat = .infinity
    /// Set when this vehicle sits too deep in a pile for its plate to be worth
    /// drawing. Kept separate from the zoom fade so neither overwrites the
    /// other — both have to agree before a plate appears.
    private var plateSuppressed = false
    private var labelFade: CGFloat = 1

    override init() {
        super.init()

        selectionRing.size = CGSize(
            width: MapVehicleAtlas.ringRadius * 2,
            height: MapVehicleAtlas.ringRadius * 2
        )
        selectionRing.colorBlendFactor = 1
        selectionRing.alpha = 0
        selectionRing.zPosition = 0
        selectionRing.isHidden = true
        addChild(selectionRing)

        chassis.zPosition = 1
        addChild(chassis)

        body.size = MapVehicleAtlas.bodySize
        body.colorBlendFactor = 1
        body.zPosition = 0
        chassis.addChild(body)

        // Anchored left so the reveal grows from the nose of the capsule; the
        // texture is a sub-rect of the same capsule, so it never squashes.
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        fill.position = CGPoint(x: -MapVehicleAtlas.bodySize.width / 2, y: 0)
        fill.colorBlendFactor = 1
        fill.zPosition = 1
        fill.isHidden = true
        chassis.addChild(fill)

        outline.size = MapVehicleAtlas.bodySize
        outline.colorBlendFactor = 1
        outline.zPosition = 2
        chassis.addChild(outline)

        plate.centerRect = MapVehicleAtlas.plateCenterRect
        plate.color = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 1)
        plate.colorBlendFactor = 1
        plate.alpha = 0.85
        plate.zPosition = 2
        plate.position = CGPoint(x: 0, y: 14)
        addChild(plate)

        label.fontSize = 7.5
        label.fontColor = MapPalette.label.withAlphaComponent(0.92)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 3
        plate.addChild(label)

        sparkGlow.size = CGSize(
            width: MapVehicleAtlas.glowRadius * 2,
            height: MapVehicleAtlas.glowRadius * 2
        )
        sparkGlow.colorBlendFactor = 1
        sparkGlow.zPosition = 0
        sparkGlow.alpha = 0
        sparkGlow.isHidden = true
        addChild(sparkGlow)

        spark.size = CGSize(
            width: MapVehicleAtlas.sparkRadius * 2,
            height: MapVehicleAtlas.sparkRadius * 2
        )
        spark.colorBlendFactor = 1
        spark.zPosition = 1
        spark.alpha = 0
        spark.isHidden = true
        addChild(spark)
    }

    /// Zoom-driven appearance: shrink, then hand over from the truck body to a
    /// point of light. The two never both carry the frame — as one fades the
    /// other takes over — so there is no moment where the vehicle reads as a
    /// smudge caught between two shapes.
    /// - Parameters:
    ///   - cameraScale: the camera's own scale, which counter-scales the node
    ///     so world geometry does not stretch it.
    ///   - semanticScale: how much smaller the vehicle should read at this
    ///     zoom, 1 when close and well under 1 when pulled back.
    func setSemanticZoom(
        cameraScale: CGFloat,
        semanticScale: CGFloat,
        chassisAlpha: CGFloat,
        sparkAlpha: CGFloat,
        labelAlpha: CGFloat
    ) {
        setScale(cameraScale * semanticScale)
        chassis.alpha = chassisAlpha
        chassis.isHidden = chassisAlpha < 0.02
        selectionRing.isHidden = chassisAlpha < 0.02 && selectionRing.alpha < 0.02
        labelFade = labelAlpha
        plate.alpha = labelAlpha * 0.85
        updatePlateVisibility()

        spark.alpha = sparkAlpha
        spark.isHidden = sparkAlpha < 0.02
        sparkGlow.alpha = sparkAlpha * 0.42
        sparkGlow.isHidden = spark.isHidden
        // Undo only the semantic shrink, not the camera scale: the spark then
        // holds a constant on-screen size while the truck around it shrinks
        // away. A star does not get smaller — it becomes the only thing left.
        let counter = semanticScale > 0.001 ? 1 / semanticScale : 1
        spark.setScale(counter)
        sparkGlow.setScale(counter)
    }

    func setSparkColor(_ color: UIColor) {
        guard spark.color != color else { return }
        spark.color = color
        sparkGlow.color = color
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        marker: MapVehicleMarker,
        accent: UIColor,
        isSelected: Bool,
        cameraScale: CGFloat
    ) {
        _ = cameraScale
        let heading = Self.stabilizedHeading(marker.headingRadians)
        if marker.isMoving {
            // Rotating to a heading it is already turning towards restarts the
            // action every tick and the vehicle never finishes a turn.
            if abs(Self.angleDelta(heading, appliedHeading)) > 0.01 {
                appliedHeading = heading
                chassis.run(
                    .rotate(
                        toAngle: heading,
                        duration: SimulationSpeed.clockTickSeconds,
                        shortestUnitArc: true
                    ),
                    withKey: "heading"
                )
            }
        } else if chassis.zRotation != heading {
            chassis.removeAction(forKey: "heading")
            chassis.zRotation = heading
            appliedHeading = heading
        }

        // The capsule is a tank and the fill is what is in it. While loading or
        // unloading that level is animating, so the service progress drives it;
        // the rest of the time it is simply how full the vehicle is. One shape,
        // one meaning, whatever the vehicle happens to be doing.
        let level = marker.serviceProgress ?? marker.loadFraction
        let reveal = MapVehicleAtlas.fill(progress: level)
        if appliedFillStep != reveal.width {
            appliedFillStep = reveal.width
            fill.texture = reveal.texture
            fill.size = CGSize(width: reveal.width, height: MapVehicleAtlas.bodySize.height)
        }
        fill.isHidden = level <= 0.001
        fill.color = accent
        setBody(
            MapPalette.unfilledVehicleBody(for: accent),
            alpha: marker.isMoving ? 1 : 0.85,
            outline: accent
        )

        if appliedCode != marker.displayCode {
            appliedCode = marker.displayCode
            label.text = marker.displayCode
            let width = max(28, CGFloat(marker.displayCode.count) * 5.2 + 12)
            if appliedPlateWidth != width {
                appliedPlateWidth = width
                plate.size = CGSize(width: width, height: MapVehicleAtlas.plateHeight)
            }
        }

        let labelColor = isSelected ? accent : MapPalette.label.withAlphaComponent(0.85)
        if appliedLabelColor != labelColor {
            appliedLabelColor = labelColor
            label.fontColor = labelColor
        }

        // Şehirde işlem: isim şehir adının üstünde. Rota üzerinde üst üste
        // binen araçlarda da aynı dikey istif — kodlar birbirini örtmesin.
        plateSuppressed = marker.labelStackIndex
            == MapSceneAdapter.VehicleLabelStacking.suppressed
        updatePlateVisibility()

        let baseY: CGFloat = marker.serviceProgress != nil ? 28 : 14
        let plateY = baseY + CGFloat(max(0, marker.labelStackIndex)) * 13
        if appliedPlateY != plateY {
            appliedPlateY = plateY
            plate.position = CGPoint(x: 0, y: plateY)
        }

        selectionRing.color = accent
        selectionRing.alpha = isSelected ? 0.7 : 0
        selectionRing.isHidden = !isSelected
    }

    private func updatePlateVisibility() {
        plate.isHidden = plateSuppressed || labelFade < 0.02
    }

    private func setBody(_ bodyColor: UIColor, alpha bodyAlpha: CGFloat, outline outlineColor: UIColor) {
        if appliedAccent != bodyColor {
            appliedAccent = bodyColor
            body.color = bodyColor
        }
        if body.alpha != bodyAlpha { body.alpha = bodyAlpha }
        if appliedOutlineColor != outlineColor {
            appliedOutlineColor = outlineColor
            outline.color = outlineColor
        }
    }

    /// Keep heading in (-π, π] so shortest-arc rotates stay smooth across the ±π wrap.
    private static func stabilizedHeading(_ radians: CGFloat) -> CGFloat {
        var value = radians
        while value <= -.pi { value += 2 * .pi }
        while value > .pi { value -= 2 * .pi }
        return value
    }

    private static func angleDelta(_ first: CGFloat, _ second: CGFloat) -> CGFloat {
        guard second.isFinite else { return .infinity }
        return atan2(sin(first - second), cos(first - second))
    }
}
