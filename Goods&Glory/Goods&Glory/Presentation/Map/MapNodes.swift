//
//  MapNodes.swift
//  Goods&Glory
//
//  The SpriteKit nodes the map draws at a city: planned-visit markers and city
//  pins with their label/badge chrome. Vehicles live in MapVehicleNode.swift.
//  Presentation only — they render a snapshot and never read game state.
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
        deliveryIcon.color = MapPalette.onBrand

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
    /// Pin radius in local points — label gap is measured from this edge.
    private static let pinRadius: CGFloat = 9
    /// Air between pin edge and city name (keeps them from kissing).
    private static let labelGap: CGFloat = 6

    private let markerContainer = SKNode()
    /// Outer disc (lighter, thin band). Inner sits flush — band ≈ 18% of radius.
    private let markerRing = SKShapeNode(circleOfRadius: pinRadius)
    /// Inner disc (darker). Same center, no gap to the ring band.
    private let marker = SKShapeNode(circleOfRadius: pinRadius * 0.82)
    /// Design 1b HQ pin: rounded square filled with the company brand color.
    private let hqMarker = SKShapeNode(
        rect: CGRect(x: -9, y: -9, width: 18, height: 18),
        cornerRadius: 5
    )
    private let hqCore = SKShapeNode(
        rect: CGRect(x: -7.2, y: -7.2, width: 14.4, height: 14.4),
        cornerRadius: 4
    )
    private let halo = SKShapeNode(circleOfRadius: 14)
    private let selectionRing = SKShapeNode(circleOfRadius: 12.5)
    /// Scaled by zoom. Carries no centering offset of its own: scaling happens
    /// about a node's own origin, so an offset here would slide the name
    /// sideways every time the zoom-driven scale changed.
    private let labelRow = SKNode()
    /// Holds the centering offset instead, inside the scaled row.
    private let labelContent = SKNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let fleetBadge = SKShapeNode(circleOfRadius: 7)
    private let fleetCount = SKLabelNode(fontNamed: "AvenirNext-Bold")
    /// Owned buildings, drawn as filled discs under the pin.
    private let facilityRow = SKNode()
    private let officeDisc = SKShapeNode(circleOfRadius: 7)
    private let warehouseDisc = SKShapeNode(circleOfRadius: 7)
    private let officeIcon = SKSpriteNode()
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

        // Two flush discs: lighter outer + darker inner. No stroke gap, no glyph.
        markerRing.fillColor = MapPalette.stationRing
        markerRing.strokeColor = .clear
        markerRing.lineWidth = 0
        markerRing.glowWidth = 0
        markerRing.isAntialiased = true
        markerRing.zPosition = 2
        markerContainer.addChild(markerRing)

        marker.fillColor = MapPalette.station
        marker.strokeColor = .clear
        marker.lineWidth = 0
        marker.glowWidth = 0
        marker.isAntialiased = true
        marker.zPosition = 3
        markerContainer.addChild(marker)

        hqMarker.fillColor = MapPalette.stationRing
        hqMarker.strokeColor = .clear
        hqMarker.lineWidth = 0
        hqMarker.zPosition = 3
        hqMarker.isHidden = true
        markerContainer.addChild(hqMarker)

        hqCore.fillColor = MapPalette.station
        hqCore.strokeColor = .clear
        hqCore.lineWidth = 0
        hqCore.zPosition = 4
        hqCore.isHidden = true
        markerContainer.addChild(hqCore)

        halo.strokeColor = MapPalette.gold.withAlphaComponent(0.55)
        halo.lineWidth = 1.35
        halo.fillColor = .clear
        halo.zPosition = 0
        halo.isHidden = true
        markerContainer.addChild(halo)

        selectionRing.strokeColor = MapPalette.gold
        selectionRing.lineWidth = 1.8
        selectionRing.fillColor = .clear
        selectionRing.zPosition = 1
        selectionRing.isHidden = true
        markerContainer.addChild(selectionRing)

        // Name sits above the pin with a deliberate gap.
        labelRow.zPosition = 4
        labelRow.position = CGPoint(x: 0, y: Self.pinRadius + Self.labelGap)
        addChild(labelRow)
        labelRow.addChild(labelContent)

        label.text = city.name
        label.fontSize = 11
        label.fontColor = MapPalette.cityLabel
        label.verticalAlignmentMode = .bottom
        label.horizontalAlignmentMode = .left
        labelContent.addChild(label)

        fleetBadge.fillColor = MapPalette.gold
        fleetBadge.strokeColor = MapPalette.water
        fleetBadge.lineWidth = 1.2
        fleetBadge.zPosition = 1
        fleetBadge.isHidden = true
        labelContent.addChild(fleetBadge)

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
        labelContent.addChild(attentionBadge)

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
            (officeDisc, officeIcon, "building.2.fill"),
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
    private var markerScale: CGFloat = 1

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
        markerRing.isHidden = isHQ
        marker.isHidden = isHQ
        hqMarker.isHidden = !isHQ
        hqCore.isHidden = !isHQ
        if isHQ {
            // Dual-tone square: brand outer, dark inner core (flush, no gap).
            hqMarker.fillColor = accent
            hqCore.fillColor = MapPalette.station
            halo.strokeColor = accent.withAlphaComponent(0.65)
        } else {
            markerRing.fillColor = isStarter
                ? MapPalette.gold.withAlphaComponent(0.85)
                : MapPalette.stationRing
            marker.fillColor = MapPalette.station
            halo.strokeColor = MapPalette.gold.withAlphaComponent(0.55)
        }
        halo.isHidden = !(isHQ || isStarter)
        selectionRing.isHidden = !isSelected
        selectionRing.strokeColor = accent
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
        guard let facilities, facilities.hasOffice || facilities.hasWarehouse else {
            facilityRow.isHidden = true
            return
        }
        facilityRow.isHidden = false
        officeDisc.isHidden = !facilities.hasOffice
        warehouseDisc.isHidden = !facilities.hasWarehouse
        // Under construction reads as a dimmed marker: present, not yet yours.
        let alpha: CGFloat = facilities.isBuilding ? 0.5 : 1
        officeDisc.fillColor = accent
        officeDisc.alpha = alpha
        warehouseDisc.fillColor = MapPalette.mint
        warehouseDisc.alpha = alpha

        let visible = [officeDisc, warehouseDisc].filter { !$0.isHidden }
        if visible.count == 1 {
            visible[0].position = .zero
        } else {
            officeDisc.position = CGPoint(x: -8, y: 0)
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

    /// Pin size only. Cheap enough to run on every pinch frame, which is the
    /// point: quantising it made the pin jump between sizes mid-gesture.
    func setMarkerScale(_ scale: CGFloat) {
        guard markerScale != scale else { return }
        markerScale = scale
        markerContainer.setScale(scale)
        facilityRow.setScale(scale)
        // Gap stays readable: pin rim + fixed air, then name.
        labelRow.position.y = Self.pinRadius * scale + Self.labelGap
        facilityRow.position.y = -(Self.pinRadius * scale + Self.labelGap + 2)
    }

    /// Name fade and the slight shrink that goes with it. Depends on which
    /// cities matter at this zoom, so it is refreshed per zoom step rather
    /// than per frame.
    func setLabelVisibility(_ labelAlpha: CGFloat) {
        labelRow.setScale(max(0.7, 0.7 + 0.3 * labelAlpha))
        label.alpha = labelAlpha
        if !attentionBadge.isHidden || !fleetBadge.isHidden {
            labelRow.isHidden = false
            labelRow.alpha = max(labelAlpha, 0.95)
        } else {
            labelRow.alpha = labelAlpha
            labelRow.isHidden = labelAlpha < 0.02
        }
    }

    private func layoutLabelRow() {
        label.position = .zero
        // Gerçek glif kutusu: isim işaret altında ortalı kalsın. Ofset ölçeklenen
        // satırın *içinde* durur, yoksa zoom ölçeği ismi yana kaydırır.
        let nameFrame = label.frame
        if nameFrame.width > 1 {
            labelContent.position.x = -nameFrame.midX
        } else {
            labelContent.position.x = -(CGFloat(cityName.count) * 6.2) / 2
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
