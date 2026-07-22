//
//  RouteBuilderView+Visits.swift
//  Goods&Glory
//
//  The lap as an editable list of city visits: reorder, open the work
//  picker, and read at a glance what happens at each stop.
//

import SwiftUI

extension RouteBuilderView {
    func routeEditorList(_ route: Route) -> some View {
        let visits = cityVisits(route)
        return List {
            Section {
                if visits.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "map")
                            .foregroundStyle(accent)
                        Text("Tap a city on the map to add the first visit.")
                            .font(.gg(12, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                    .plainListRow()
                } else {
                    ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                        compactVisitRow(visit, number: index + 1, route: route)
                            .dropDestination(for: String.self) { items, location in
                                guard canEdit(route),
                                      let rawID = items.first,
                                      let draggedID = Int(rawID),
                                      draggedID != visit.id else { return false }
                                dropVisit(
                                    draggedID,
                                    on: visit.id,
                                    placeAfter: location.y > 32,
                                    route: route
                                )
                                return true
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if canEdit(route) {
                                    Button(role: .destructive) {
                                        apply(.removeRouteVisit(routeID: route.id, visitStopID: visit.id))
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .accessibilityAction(named: "Move earlier") {
                                moveVisit(visit.id, by: -1, route: route)
                            }
                            .accessibilityAction(named: "Move later") {
                                moveVisit(visit.id, by: 1, route: route)
                            }
                            .plainListRow()
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(accent)
                    Text("Add another city from the map")
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 5)
                .plainListRow()
            } header: {
                HStack {
                    Text("ROUTE PLAN")
                    Spacer()
                    Text("\(visits.count) cit\(visits.count == 1 ? "y" : "ies") · \(taskCount(route)) tasks")
                }
                .font(.gg(10.5, .heavy))
                .foregroundStyle(Theme.textTertiary)
                .textCase(nil)
            }

            Section {
                routeActions(route)
                    .plainListRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 14, for: .scrollContent)
        .contentMargins(.bottom, Layout.tabBarClearance, for: .scrollContent)
    }

    func compactVisitRow(_ visit: CityVisit, number: Int, route: Route) -> some View {
        let tasks = visit.stops.filter { !isTravel($0.task) }
        return HStack(spacing: 10) {
            Text("\(number)")
                .font(.gg(12, .heavy))
                .foregroundStyle(Theme.onBrand)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent))

            VStack(alignment: .leading, spacing: 5) {
                Text(session.cityName(visit.cityID))
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if tasks.isEmpty {
                        compactTaskChip(text: "Drive only", symbol: "arrow.right", color: Theme.textTertiary)
                    } else {
                        ForEach(Array(tasks.prefix(2))) { stop in
                            compactTaskChip(
                                text: taskChipText(stop.task),
                                symbol: stop.task.displaySymbol,
                                color: stop.task.displayTint(accent: accent)
                            )
                        }
                        if tasks.count > 2 {
                            Text("+\(tasks.count - 2)")
                                .font(.gg(9.5, .heavy))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Theme.surface))
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                selectedVisit = visit
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(canAppend(route) ? accent : Theme.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAppend(route))
            .accessibilityLabel("Add work in \(session.cityName(visit.cityID))")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canEdit(route) ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
                .draggable(String(visit.id))
                .allowsHitTesting(canEdit(route))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    func compactTaskChip(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .heavy))
            Text(text)
                .font(.gg(9, .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 1))
    }

}
