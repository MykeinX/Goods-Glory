//
//  CompanyFoundingView.swift
//  Goods&Glory
//
//  Founding flow, two stable stages driven by a simple @State switch (no
//  fragile navigation teardown):
//    1. Identity — name, brand color and emblem on one screen with a live
//       preview. Everything stays visible while typing.
//    2. Headquarters — pick a starter city on the interactive world map.
//

import SwiftUI

struct FoundingDraft {
    var companyName: String = ""
    var colorHex: String = FoundingOptions.colors[0]
    var emblemSymbol: String = FoundingOptions.emblems[0]

    var accentColor: Color { Color(hex: colorHex) }
    var isNameValid: Bool { !companyName.trimmingCharacters(in: .whitespaces).isEmpty }
}

enum FoundingOptions {
    static let colors = [
        "#FFB037", "#4FD6A4", "#57B2FF", "#FF6B5E",
        "#9B8CFF", "#F2994A", "#2EA043", "#E06C9A"
    ]
    static let emblems = [
        "shippingbox.fill", "cube.fill", "globe.americas.fill", "bolt.fill",
        "star.fill", "flame.fill", "arrow.triangle.swap", "diamond.fill"
    ]
}

struct CompanyFoundingView: View {
    @Environment(GameSession.self) private var session

    private enum Stage { case identity, headquarters }
    @State private var stage: Stage = .identity
    @State private var draft = FoundingDraft()

    var body: some View {
        ZStack {
            switch stage {
            case .identity:
                IdentityStageView(
                    draft: $draft,
                    onCancel: { session.cancelFounding() },
                    onContinue: { stage = .headquarters }
                )
                .transition(.opacity)
            case .headquarters:
                HeadquartersStageView(
                    draft: draft,
                    onBack: { stage = .identity }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: stage)
        .tint(draft.accentColor)
    }
}

// MARK: - Stage 1: Identity

private struct IdentityStageView: View {
    @Binding var draft: FoundingDraft
    let onCancel: () -> Void
    let onContinue: () -> Void

    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            ThemeBackground(showsRoutes: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        StepIndicator(current: 0, total: 2, accent: draft.accentColor)
                        Spacer()
                        Button(action: onCancel) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Theme.surface))
                                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                        }
                    }
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Found your company")
                            .font(.gg(30, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Name it and shape its brand.")
                            .font(.gg(14, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }

                    previewCard

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Company Name")
                        TextField("e.g. Summit Freight", text: $draft.companyName)
                            .focused($nameFocused)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { nameFocused = false }
                            .font(.gg(16, .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .tint(draft.accentColor)
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(nameFocused ? draft.accentColor : Theme.stroke, lineWidth: nameFocused ? 1.6 : 1))
                    }

                    colorPicker
                    emblemPicker

                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                nameFocused = false
                onContinue()
            } label: {
                Label("Choose Headquarters", systemImage: "mappin.and.ellipse")
            }
            .buttonStyle(PrimaryButtonStyle(tint: draft.accentColor))
            .disabled(!draft.isNameValid)
            .opacity(draft.isNameValid ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.backgroundBottom.opacity(0.9).ignoresSafeArea(edges: .bottom))
        }
    }

    private var previewCard: some View {
        HStack(spacing: 14) {
            CompanyMark(emblemSymbol: draft.emblemSymbol, color: draft.accentColor, size: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.isNameValid ? draft.companyName : String(localized: "Your Company"))
                    .font(.gg(18, .heavy))
                    .foregroundStyle(draft.isNameValid ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Text("Est. Day 1 — Founder & CEO: You")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .surfacePanel(cornerRadius: 20, selected: true, accent: draft.accentColor)
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Corporate Color")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                ForEach(FoundingOptions.colors, id: \.self) { hex in
                    let isSelected = hex == draft.colorHex
                    Button {
                        draft.colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(height: 34)
                            .overlay(Circle().stroke(.white, lineWidth: isSelected ? 2.5 : 0).padding(2))
                            .shadow(color: isSelected ? Color(hex: hex).opacity(0.6) : .clear, radius: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var emblemPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("Emblem")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(FoundingOptions.emblems, id: \.self) { symbol in
                    let isSelected = symbol == draft.emblemSymbol
                    Button {
                        draft.emblemSymbol = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.title3)
                            .foregroundStyle(isSelected ? draft.accentColor : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isSelected ? draft.accentColor.opacity(0.16) : Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isSelected ? draft.accentColor : Theme.stroke, lineWidth: isSelected ? 1.6 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Stage 2: Headquarters on the interactive map

private struct HeadquartersStageView: View {
    @Environment(GameSession.self) private var session
    let draft: FoundingDraft
    let onBack: () -> Void

    @State private var inspectedCityID: CityID?

    var body: some View {
        ZStack {
            InteractiveMapView(
                catalog: session.catalog,
                hqCityID: nil,
                highlightsStarterCities: true,
                accentColorHex: draft.colorHex,
                selectedCityID: $inspectedCityID
            )
            .ignoresSafeArea()

            LinearGradient(colors: [Theme.backgroundTop, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.surfaceGlass))
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        StepIndicator(current: 1, total: 2, accent: draft.accentColor)
                        Text("Choose your headquarters")
                            .font(.gg(18, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Tap a glowing city to inspect it.")
                            .font(.gg(11.5, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)

                Spacer()

                if let cityID = inspectedCityID, let city = session.catalog.city(cityID) {
                    CityFoundingCard(
                        city: city,
                        roadCount: session.catalog.roads.filter { $0.from == city.roadNodeID || $0.to == city.roadNodeID }.count,
                        accent: draft.accentColor,
                        onFound: { establishHQ(in: city) }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: inspectedCityID)
        }
    }

    private func establishHQ(in city: CityDefinition) {
        let identity = CompanyIdentity(
            name: draft.companyName.trimmingCharacters(in: .whitespaces),
            colorHex: draft.colorHex,
            emblemSymbol: draft.emblemSymbol
        )
        // Deferred out of the current UI transaction for a clean teardown.
        DispatchQueue.main.async {
            session.startNewGame(identity: identity, hqCity: city.id)
        }
    }
}

private struct CityFoundingCard: View {
    let city: CityDefinition
    let roadCount: Int
    let accent: Color
    let onFound: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.name)
                        .font(.gg(22, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(city.country)
                        .font(.gg(12, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if city.isStarterCity {
                    TagPill(text: "Starter City", color: accent)
                }
            }

            HStack(spacing: 8) {
                StatChip(symbol: "person.2", text: city.population.formatted(.number.notation(.compactName)))
                StatChip(symbol: "road.lanes", text: "\(roadCount)")
                if city.hasRailFreightAccess { StatChip(symbol: "tram.fill", text: String(localized: "Rail")) }
                if city.hasAirCargoAccess { StatChip(symbol: "airplane", text: String(localized: "Air")) }
                if city.hasSeaPortAccess { StatChip(symbol: "ferry.fill", text: String(localized: "Sea")) }
            }

            if city.isStarterCity {
                Button(action: onFound) {
                    Text("Establish HQ in \(city.name)")
                }
                .buttonStyle(PrimaryButtonStyle(tint: accent))
            } else {
                Label("Not available as a starting city. Expand here later.", systemImage: "lock.fill")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.surfaceGlass))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(city.isStarterCity ? accent.opacity(0.7) : Theme.stroke, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
    }
}
