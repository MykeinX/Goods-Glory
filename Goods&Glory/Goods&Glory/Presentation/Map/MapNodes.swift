//
//  MapNodes.swift
//  Goods&Glory
//
//  The SpriteKit nodes the map draws: planned-visit markers, city pins with
//  their label/badge chrome, and vehicle sprites. Presentation only — they
//  render a snapshot and never read game state.
//

import SpriteKit
import UIKit

// MARK: - Map nodes

@MainActor
final class MapPlannedVisitNode: SKNode {
    private let marker = SKShapeNode(circleOfRadius: 13)
    private let stepLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let pickupBadge = SKShapeNode(circleOfRadius: 7.5)
    private let deliveryBadge = SKShapeNode(circleOfRadius: 7.5)
    private let pickupIcon = SKSpriteNode()
    private let deliveryIcon = SKSpriteNode()

    override init() {
        super.init()

        marker.fillColor = MapPalette.water
        marker.lineWidth = 2.2
        marker.zPosition = 1
        addChild(marker)

        stepLabel.fontSize = 9
        stepLabel.verticalAlignmentMode = .center
        stepLabel.horizontalAlignmentMode = .center
        stepLabel.position = CGPoint(x: 0, y: -0.5)
        stepLabel.zPosition = 2
        addChild(stepLabel)

        configureBadge(
            pickupBadge,
            icon: pickupIcon,
            symbol: "tray.and.arrow.up.fill"
        )
        configureBadge(
            deliveryBadge,
            icon: deliveryIcon,
            symbol: "tray.and.arrow.down.fill"
        )
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(marker value: MapPlannedVisitMarker, accent: UIColor) {
        let numberText = value.stepNumbers.map(String.init).joined(separator: "·")
        stepLabel.text = numberText
        stepLabel.fontSize = numberText.count > 4 ? 7 : (numberText.count > 2 ? 8 : 9)
        stepLabel.fontColor = accent
        marker.strokeColor = accent
        marker.glowWidth = 0.5

        pickupBadge.isHidden = !value.hasPickup
        deliveryBadge.isHidden = !value.hasDelivery
        pickupBadge.fillColor = accent
        pickupBadge.strokeColor = MapPalette.water
        deliveryBadge.fillColor = MapPalette.mint
        deliveryBadge.strokeColor = MapPalette.water
        pickupIcon.color = MapPalette.onBrand
        deliveryIcon.color = MapPalette.water

        let visibleBadges = [pickupBadge, deliveryBadge].filter { !$0.isHidden }
        if visibleBadges.count == 1 {
            visibleBadges[0].position = CGPoint(x: 0, y: -21)
        } else {
            pickupBadge.position = CGPoint(x: -9, y: -21)
            deliveryBadge.position = CGPoint(x: 9, y: -21)
        }
    }

    private func configureBadge(
        _ badge: SKShapeNode,
        icon: SKSpriteNode,
        symbol: String
    ) {
        badge.lineWidth = 1.2
        badge.zPosition = 3
        addChild(badge)

        icon.texture = Self.symbolTexture(named: symbol)
        icon.size = CGSize(width: 9, height: 9)
        icon.colorBlendFactor = 1
        icon.zPosition = 1
        badge.addChild(icon)
    }

    private static func symbolTexture(named name: String) -> SKTexture? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 10, weight: .black)
        guard let image = UIImage(
            systemName: name,
            withConfiguration: configuration
        )?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
            return nil
        }
        return SKTexture(image: image)
    }
}

@MainActor
final class MapCityNode: SKNode {
    private let markerContainer = SKNode()
    private let marker = SKShapeNode(circleOfRadius: 7)
    /// Design 1b HQ pin: rounded square filled with the company brand color.
    private let hqMarker = SKShapeNode(
        rect: CGRect(x: -8, y: -8, width: 16, height: 16),
        cornerRadius: 5
    )
    private let halo = SKShapeNode(circleOfRadius: 12)
    private let selectionRing = SKShapeNode(circleOfRadius: 10)
    private let labelRow = SKNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let fleetBadge = SKShapeNode(circleOfRadius: 7)
    private let fleetCount = SKLabelNode(fontNamed: "AvenirNext-Bold")
    /// Owned buildings, drawn as filled discs under the pin.
    private let facilityRow = SKNode()
    private let branchDisc = SKShapeNode(circleOfRadius: 7)
    private let warehouseDisc = SKShapeNode(circleOfRadius: 7)
    private let branchIcon = SKSpriteNode()
    private let warehouseIcon = SKSpriteNode()
    /// Freight needing attention. Colour carries the urgency; the number
    /// carries the volume. Everything else lives in the city screen.
    private let attentionBadge = SKShapeNode(circleOfRadius: 7)
    private let attentionCount = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let cityName: String

    init(city: CityDefinition) {
        cityName = city.name
        super.init()
        markerContainer.zPosition = 2
        addChild(markerContainer)

        marker.fillColor = MapPalette.city
        marker.strokeColor = MapPalette.cityStroke
        marker.lineWidth = 1.8
        marker.zPosition = 2
        markerContainer.addChild(marker)

        hqMarker.fillColor = MapPalette.gold
        hqMarker.strokeColor = MapPalette.water
        hqMarker.lineWidth = 1.5
        hqMarker.zPosition = 3
        hqMarker.isHidden = true
        markerContainer.addChild(hqMarker)

        halo.strokeColor = MapPalette.city
        halo.lineWidth = 1.5
        halo.fillColor = .clear
        halo.zPosition = 0
        halo.isHidden = true
        markerContainer.addChild(halo)

        selectionRing.strokeColor = .white
        selectionRing.lineWidth = 2
        selectionRing.fillColor = .clear
        selectionRing.zPosition = 1
        selectionRing.isHidden = true
        markerContainer.addChild(selectionRing)

        labelRow.zPosition = 4
        labelRow.position = CGPoint(x: 0, y: 11)
        addChild(labelRow)

        label.text = city.name
        label.fontSize = 11
        label.fontColor = MapPalette.label
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        labelRow.addChild(label)

        fleetBadge.fillColor = MapPalette.gold
        fleetBadge.strokeColor = MapPalette.water
        fleetBadge.lineWidth = 1.2
        fleetBadge.zPosition = 1
        fleetBadge.isHidden = true
        labelRow.addChild(fleetBadge)

        // Baseline + left: frame ortası dairenin (0,0) noktasına taşınır (optik ortalama).
        fleetCount.fontSize = 9
        fleetCount.fontColor = MapPalette.water
        fleetCount.verticalAlignmentMode = .baseline
        fleetCount.horizontalAlignmentMode = .left
        fleetCount.zPosition = 2
        fleetBadge.addChild(fleetCount)

        attentionBadge.strokeColor = MapPalette.water
        attentionBadge.lineWidth = 1.2
        attentionBadge.zPosition = 1
        attentionBadge.isHidden = true
        labelRow.addChild(attentionBadge)

        attentionCount.fontSize = 9
        attentionCount.verticalAlignmentMode = .baseline
        attentionCount.horizontalAlignmentMode = .left
        attentionCount.zPosition = 2
        attentionBadge.addChild(attentionCount)

        // Facility strip sits below the pin so it never collides with the name.
        // Each building is a filled disc with a white glyph: at map scale a bare
        // tinted glyph reads as a smudge, a disc reads as a deliberate marker.
        facilityRow.zPosition = 5
        facilityRow.position = CGPoint(x: 0, y: -15)
        facilityRow.isHidden = true
        addChild(facilityRow)
        for (disc, icon, symbol) in [
            (branchDisc, branchIcon, "building.2.fill"),
            (warehouseDisc, warehouseIcon, "shippingbox.fill")
        ] {
            disc.lineWidth = 1.4
            disc.strokeColor = MapPalette.water
            disc.zPosition = 1
            disc.isHidden = true
            facilityRow.addChild(disc)

            icon.texture = Self.symbolTexture(named: symbol)
            icon.size = CGSize(width: 9, height: 9)
            icon.colorBlendFactor = 1
            icon.color = .white
            icon.zPosition = 2
            disc.addChild(icon)
        }

        layoutLabelRow()
    }

    /// Rendered at 3x and downscaled so the glyph stays crisp when the camera
    /// zooms in — a 9pt symbol rasterised at 9pt turns to mush.
    private static func symbolTexture(named name: String) -> SKTexture? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 27, weight: .heavy)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Everything `configure` reads. Re-applying an identical appearance costs
    /// several SKShapeNode colour writes plus three SKLabelNode frame
    /// measurements (each a glyph layout), so identical input is skipped.
    private struct Appearance: Equatable {
        let isHQ: Bool
        let isStarter: Bool
        let isSelected: Bool
        let accent: UIColor
        let idleFleetCount: Int
        let facilities: MapCityFacilities?
        let attention: MapCityAttention?
    }

    private var appearance: Appearance?
    private var isPulseSuspended = false

    func configure(
        isHQ: Bool,
        isStarter: Bool,
        isSelected: Bool,
        accent: UIColor,
        idleFleetCount: Int,
        facilities: MapCityFacilities?,
        attention: MapCityAttention?
    ) {
        let next = Appearance(
            isHQ: isHQ,
            isStarter: isStarter,
            isSelected: isSelected,
            accent: accent,
            idleFleetCount: idleFleetCount,
            facilities: facilities,
            attention: attention
        )
        guard appearance != next else { return }
        appearance = next

        configureFacilityStrip(facilities, accent: accent)
        configureAttentionBadge(attention, isHQ: isHQ)
        marker.isHidden = isHQ
        hqMarker.isHidden = !isHQ
        if isHQ {
            hqMarker.fillColor = accent
            hqMarker.strokeColor = MapPalette.water
            halo.strokeColor = accent
        } else {
            let color = isStarter ? MapPalette.gold : MapPalette.city
            marker.fillColor = color
            marker.strokeColor = isStarter ? MapPalette.gold : MapPalette.cityStroke
            halo.strokeColor = color
        }
        halo.isHidden = !(isHQ || isStarter)
        selectionRing.isHidden = !isSelected
        selectionRing.strokeColor = isHQ ? accent : .white
        refreshHaloPulse()

        let showBadge = idleFleetCount > 0
        fleetBadge.isHidden = !showBadge
        fleetCount.isHidden = !showBadge
        if showBadge {
            fleetBadge.fillColor = accent
            fleetCount.fontColor = MapPalette.onBrand
            fleetCount.text = idleFleetCount > 9 ? "9+" : "\(idleFleetCount)"
        }
        layoutLabelRow()
    }

    private func configureFacilityStrip(_ facilities: MapCityFacilities?, accent: UIColor) {
        guard let facilities, facilities.hasBranch || facilities.hasWarehouse else {
            facilityRow.isHidden = true
            return
        }
        facilityRow.isHidden = false
        branchDisc.isHidden = !facilities.hasBranch
        warehouseDisc.isHidden = !facilities.hasWarehouse
        // Under construction reads as a dimmed marker: present, not yet yours.
        let alpha: CGFloat = facilities.isBuilding ? 0.5 : 1
        branchDisc.fillColor = accent
        branchDisc.alpha = alpha
        warehouseDisc.fillColor = MapPalette.mint
        warehouseDisc.alpha = alpha

        let visible = [branchDisc, warehouseDisc].filter { !$0.isHidden }
        if visible.count == 1 {
            visible[0].position = .zero
        } else {
            branchDisc.position = CGPoint(x: -8, y: 0)
            warehouseDisc.position = CGPoint(x: 8, y: 0)
        }
    }

    private func configureAttentionBadge(_ attention: MapCityAttention?, isHQ: Bool) {
        guard let attention, attention.total > 0 else {
            attentionBadge.isHidden = true
            return
        }
        attentionBadge.isHidden = false
        attentionBadge.fillColor = Self.urgencyColor(attention.urgency)
        attentionCount.fontColor = attention.urgency >= 0.5 ? .white : MapPalette.onBrand
        attentionCount.text = attention.total > 9 ? "9+" : "\(attention.total)"
    }

    /// Calm while there is time, hot as the delivery window runs out.
    private static func urgencyColor(_ urgency: Double) -> UIColor {
        if urgency >= 0.85 { return MapPalette.deadhead }
        if urgency >= 0.5 { return MapPalette.gold }
        return MapPalette.mint
    }

    /// Stops the halo's `repeatForever` pulse while the map sleeps. The action
    /// is removed rather than frozen so the halo rests at full opacity instead
    /// of sitting mid-fade for as long as the player leaves the map alone.
    func setHaloPulsePaused(_ paused: Bool) {
        guard isPulseSuspended != paused else { return }
        isPulseSuspended = paused
        refreshHaloPulse()
    }

    private func refreshHaloPulse() {
        guard !halo.isHidden, !isPulseSuspended else {
            halo.removeAction(forKey: "pulse")
            halo.alpha = 1
            halo.setScale(1)
            return
        }
        guard halo.action(forKey: "pulse") == nil else { return }
        halo.run(.repeatForever(.sequence([
            .group([.scale(to: 1.35, duration: 0.8), .fadeAlpha(to: 0.18, duration: 0.8)]),
            .group([.scale(to: 0.9, duration: 0), .fadeAlpha(to: 0.85, duration: 0)])
        ])), withKey: "pulse")
    }

    func setSemanticZoom(markerScale: CGFloat, markerAlpha: CGFloat, labelAlpha: CGFloat) {
        markerContainer.setScale(markerScale)
        markerContainer.alpha = markerAlpha
        labelRow.position.y = 8 + 7 * markerScale
        labelRow.setScale(max(0.55, 0.55 + 0.45 * labelAlpha))
        labelRow.alpha = labelAlpha
        labelRow.isHidden = labelAlpha < 0.02
        facilityRow.position.y = -8 - 6 * markerScale
        facilityRow.setScale(markerScale)
        facilityRow.alpha = markerAlpha
        // The attention badge is the one thing that must survive zoom-out: it
        // is the signal the player cannot afford to miss.
        if !attentionBadge.isHidden {
            labelRow.isHidden = false
            labelRow.alpha = max(labelAlpha, 0.9)
            label.alpha = labelAlpha
        } else {
            label.alpha = 1
        }
    }

    private func layoutLabelRow() {
        label.position = .zero
        // Gerçek glif kutusu: isim işaret altında ortalı kalsın.
        let nameFrame = label.frame
        if nameFrame.width > 1 {
            labelRow.position.x = -nameFrame.midX
        } else {
            labelRow.position.x = -(CGFloat(cityName.count) * 6.2) / 2
        }
        guard !fleetBadge.isHidden || !attentionBadge.isHidden else { return }

        let gap = label.fontSize * 0.12
        let badgeRadius: CGFloat = 7
        // Rozet merkezi, isim kutusunun dikey ortası ve sağ kenarı ile hizalı.
        let nameEndX = nameFrame.width > 1
            ? nameFrame.maxX
            : CGFloat(cityName.count) * 6.2
        let nameMidY = nameFrame.width > 1 ? nameFrame.midY : 0

        // Aksiyon rozeti isme en yakın konumda: en kritik bilgi en görünür yer.
        var cursorX = nameEndX + gap + badgeRadius
        if !attentionBadge.isHidden {
            attentionBadge.position = CGPoint(x: cursorX, y: nameMidY)
            cursorX += badgeRadius * 2 + gap
        }
        if !fleetBadge.isHidden {
            fleetBadge.position = CGPoint(x: cursorX, y: nameMidY)
        }

        // Rakam bounding box'unu dairenin merkezine kilitle.
        for counter in [fleetCount, attentionCount] {
            counter.position = .zero
            let digitFrame = counter.frame
            if digitFrame.width > 0.5, digitFrame.height > 0.5 {
                counter.position = CGPoint(x: -digitFrame.midX, y: -digitFrame.midY)
            }
        }
    }
}

final class MapVehicleNode: SKNode {
    private static let bodyRect = CGRect(x: -5.5, y: -3.5, width: 11, height: 7)
    private static let bodyCorner: CGFloat = 2.4

    private let selectionRing = SKShapeNode(circleOfRadius: 9)
    private let chassis = SKNode()
    /// Dim full capsule (empty / traveling base).
    private let body = SKShapeNode(
        rect: MapVehicleNode.bodyRect,
        cornerRadius: MapVehicleNode.bodyCorner
    )
    /// Loading/unloading fill that grows left → right inside the capsule.
    private let fillCrop = SKCropNode()
    private let fillBody = SKShapeNode(
        rect: MapVehicleNode.bodyRect,
        cornerRadius: MapVehicleNode.bodyCorner
    )
    private let fillMask = SKSpriteNode(color: .white, size: CGSize(width: 11, height: 7))
    private let outline = SKShapeNode(
        rect: MapVehicleNode.bodyRect,
        cornerRadius: MapVehicleNode.bodyCorner
    )
    private let labelBackground = SKShapeNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
    /// What a vehicle becomes when the camera pulls back far enough that a
    /// truck silhouette is smaller than the ink it is drawn with: a point of
    /// light. Pulling back then reads as watching traffic move across a
    /// continent rather than losing sight of it.
    private let spark = SKShapeNode(circleOfRadius: 2.6)
    private let sparkGlow = SKShapeNode(circleOfRadius: 6)

    override init() {
        super.init()
        selectionRing.fillColor = .clear
        selectionRing.lineWidth = 1.4
        selectionRing.alpha = 0
        selectionRing.zPosition = 0
        addChild(selectionRing)

        chassis.zPosition = 1
        addChild(chassis)

        body.fillColor = .white
        body.strokeColor = .clear
        body.lineWidth = 0
        body.zPosition = 0
        chassis.addChild(body)

        fillBody.fillColor = .white
        fillBody.strokeColor = .clear
        fillBody.lineWidth = 0
        fillCrop.addChild(fillBody)
        fillMask.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillMask.position = CGPoint(x: Self.bodyRect.minX, y: 0)
        fillCrop.maskNode = fillMask
        fillCrop.zPosition = 1
        fillCrop.isHidden = true
        chassis.addChild(fillCrop)

        outline.fillColor = .clear
        outline.strokeColor = MapPalette.water
        outline.lineWidth = 1
        outline.zPosition = 2
        chassis.addChild(outline)

        labelBackground.fillColor = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 0.85)
        labelBackground.strokeColor = .clear
        labelBackground.zPosition = 2
        labelBackground.position = CGPoint(x: 0, y: 14)
        addChild(labelBackground)

        label.fontSize = 7.5
        label.fontColor = MapPalette.label.withAlphaComponent(0.92)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 3
        labelBackground.addChild(label)

        sparkGlow.strokeColor = .clear
        sparkGlow.zPosition = 0
        sparkGlow.alpha = 0
        addChild(sparkGlow)

        spark.strokeColor = .clear
        spark.zPosition = 1
        spark.alpha = 0
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
        labelBackground.alpha = labelAlpha
        labelBackground.isHidden = labelAlpha < 0.02

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
        spark.fillColor = color
        sparkGlow.fillColor = color
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
            chassis.run(
                .rotate(
                    toAngle: heading,
                    duration: SimulationSpeed.clockTickSeconds,
                    shortestUnitArc: true
                ),
                withKey: "heading"
            )
        } else {
            chassis.removeAction(forKey: "heading")
            chassis.zRotation = heading
        }

        if let progress = marker.serviceProgress {
            let clamped = max(0, min(1, progress))
            body.fillColor = accent
            body.alpha = 0.18
            fillCrop.isHidden = false
            fillBody.fillColor = accent
            fillMask.size = CGSize(
                width: max(0.35, Self.bodyRect.width * CGFloat(clamped)),
                height: Self.bodyRect.height
            )
            outline.strokeColor = accent
        } else {
            fillCrop.isHidden = true
            body.fillColor = accent
            body.alpha = marker.isMoving ? 1 : 0.85
            outline.strokeColor = MapPalette.water
        }

        label.text = marker.displayCode
        label.fontColor = isSelected ? accent : MapPalette.label.withAlphaComponent(0.85)
        let textWidth = max(28, CGFloat(marker.displayCode.count) * 5.2 + 12)
        labelBackground.path = CGPath(
            roundedRect: CGRect(x: -textWidth / 2, y: -5.5, width: textWidth, height: 11),
            cornerWidth: 5.5,
            cornerHeight: 5.5,
            transform: nil
        )
        // Şehirde işlem: isim şehir adının üstünde. Rota üzerinde üst üste
        // binen araçlarda da aynı dikey istif — kodlar birbirini örtmesin.
        let baseY: CGFloat = marker.serviceProgress != nil ? 28 : 14
        let stackStep: CGFloat = 13
        labelBackground.position = CGPoint(
            x: 0,
            y: baseY + CGFloat(marker.labelStackIndex) * stackStep
        )

        selectionRing.strokeColor = accent
        selectionRing.alpha = isSelected ? 0.7 : 0
    }

    /// Keep heading in (-π, π] so shortest-arc rotates stay smooth across the ±π wrap.
    private static func stabilizedHeading(_ radians: CGFloat) -> CGFloat {
        var value = radians
        while value <= -.pi { value += 2 * .pi }
        while value > .pi { value -= 2 * .pi }
        return value
    }
}

// Shared by GameMapScene extensions (Camera / Snapshot / Terrain) across files.
extension CGMutablePath {
    func addClosedPolyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
        closeSubpath()
    }

    func addOpenPolyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self.init(red: 0.12, green: 0.44, blue: 0.92, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
