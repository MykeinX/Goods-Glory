//
//  InteractiveMapView.swift
//  Goods&Glory
//
//  SwiftUI boundary around the SpriteKit world map. All management UI stays
//  in SwiftUI; only map drawing, camera interaction and live map sprites enter
//  SpriteKit.
//

import SpriteKit
import SwiftUI

struct InteractiveMapView: View {
    let catalog: GameCatalog
    var hqCityID: CityID?
    var highlightsStarterCities: Bool = false
    var accentColorHex: String
    var renderSnapshot: MapRenderSnapshot = .empty
    @Binding var selectedCityID: CityID?

    var body: some View {
        SpriteKitMapSurface(
            catalog: catalog,
            hqCityID: hqCityID,
            highlightsStarterCities: highlightsStarterCities,
            accentColorHex: accentColorHex,
            renderSnapshot: renderSnapshot,
            selectedCityID: $selectedCityID
        )
        .background(Theme.backgroundTop)
        .clipped()
        .accessibilityLabel("Interactive logistics map")
        .accessibilityHint("Pan and zoom the map, then tap a city for details.")
    }
}

private struct SpriteKitMapSurface: UIViewRepresentable {
    let catalog: GameCatalog
    let hqCityID: CityID?
    let highlightsStarterCities: Bool
    let accentColorHex: String
    let renderSnapshot: MapRenderSnapshot
    @Binding var selectedCityID: CityID?

    func makeCoordinator() -> Coordinator {
        let geography: MapGeographyDefinition
        do {
            geography = try MapGeographyDefinition.load(from: .main)
        } catch {
            assertionFailure("Map geography failed to load: \(error)")
            geography = .empty
        }
        return Coordinator(
            scene: GameMapScene(
                catalog: catalog,
                projection: MapProjection(),
                geography: geography
            ),
            selection: $selectedCityID
        )
    }

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.backgroundColor = .clear
        view.allowsTransparency = false
        view.isMultipleTouchEnabled = true
        view.presentScene(context.coordinator.scene)
        context.coordinator.installGestures(on: view)
        context.coordinator.applyConfiguration(
            hqCityID: hqCityID,
            selectedCityID: selectedCityID,
            highlightsStarterCities: highlightsStarterCities,
            accentColorHex: accentColorHex,
            force: true
        )
        context.coordinator.applySnapshot(renderSnapshot, force: true)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        context.coordinator.selection = $selectedCityID
        // Clock ticks rewrite GameState every second; skip no-op map updates so
        // idle maps do not restyle cities / rebuild routes on every tick.
        context.coordinator.applyConfiguration(
            hqCityID: hqCityID,
            selectedCityID: selectedCityID,
            highlightsStarterCities: highlightsStarterCities,
            accentColorHex: accentColorHex,
            force: false
        )
        context.coordinator.applySnapshot(renderSnapshot, force: false)
    }

    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) {
        view.presentScene(nil)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene: GameMapScene
        var selection: Binding<CityID?>

        private var lastHQCityID: CityID?
        private var lastSelectedCityID: CityID?
        private var lastHighlightsStarterCities: Bool?
        private var lastAccentColorHex: String?
        private var lastSnapshot: MapRenderSnapshot?

        init(scene: GameMapScene, selection: Binding<CityID?>) {
            self.scene = scene
            self.selection = selection
            super.init()
            scene.onCitySelected = { [weak self] cityID in
                self?.selection.wrappedValue = cityID
            }
        }

        func applyConfiguration(
            hqCityID: CityID?,
            selectedCityID: CityID?,
            highlightsStarterCities: Bool,
            accentColorHex: String,
            force: Bool
        ) {
            let changed = force
                || lastHQCityID != hqCityID
                || lastSelectedCityID != selectedCityID
                || lastHighlightsStarterCities != highlightsStarterCities
                || lastAccentColorHex != accentColorHex
            guard changed else { return }
            lastHQCityID = hqCityID
            lastSelectedCityID = selectedCityID
            lastHighlightsStarterCities = highlightsStarterCities
            lastAccentColorHex = accentColorHex
            scene.configure(
                hqCityID: hqCityID,
                selectedCityID: selectedCityID,
                highlightsStarterCities: highlightsStarterCities,
                accentColorHex: accentColorHex
            )
        }

        func applySnapshot(_ snapshot: MapRenderSnapshot, force: Bool) {
            guard force || lastSnapshot != snapshot else { return }
            lastSnapshot = snapshot
            scene.apply(snapshot: snapshot)
        }

        func installGestures(on view: SKView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 2
            pan.delegate = self
            view.addGestureRecognizer(pan)

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .changed, let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            scene.pan(by: translation)
            gesture.setTranslation(.zero, in: view)
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed, let view = gesture.view else { return }
            scene.zoom(by: gesture.scale, anchoredAt: gesture.location(in: view))
            gesture.scale = 1
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view, gesture.state == .ended else { return }
            scene.selectCity(at: gesture.location(in: view))
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard gestureRecognizer.view === otherGestureRecognizer.view else { return false }
            return (gestureRecognizer is UIPanGestureRecognizer
                    && otherGestureRecognizer is UIPinchGestureRecognizer)
                || (gestureRecognizer is UIPinchGestureRecognizer
                    && otherGestureRecognizer is UIPanGestureRecognizer)
        }
    }
}
