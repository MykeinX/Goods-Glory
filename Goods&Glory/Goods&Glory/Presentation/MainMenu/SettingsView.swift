//
//  SettingsView.swift
//  Goods&Glory
//
//  Player preferences, reachable from the title screen. Every row here is
//  wired to real behaviour; destructive data actions live at the bottom
//  behind an in-game confirmation card.
//

import SwiftUI

struct SettingsView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @Bindable private var settings = AppSettings.shared

    @State private var showsDeleteConfirmation = false

    var body: some View {
        ZStack {
            ThemeBackground(showsRoutes: false)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    SettingsGroup("Presentation") {
                        SettingsToggle(
                            title: String(localized: "Animated title background"),
                            detail: String(localized: "Moving freight network on the main menu. Turn off to save battery."),
                            systemImage: "sparkles",
                            isOn: $settings.animatedTitleBackground
                        )
                        SettingsDivider()
                        SettingsToggle(
                            title: String(localized: "Event notifications"),
                            detail: String(localized: "Toasts for deliveries, purchases and milestones."),
                            systemImage: "bell.badge.fill",
                            isOn: $settings.showsGameplayToasts
                        )
                    }

                    SettingsGroup("Gameplay") {
                        SettingsToggle(
                            title: String(localized: "Resume paused"),
                            detail: String(localized: "Continue loads the campaign with time stopped, so you can look around first."),
                            systemImage: "pause.circle.fill",
                            isOn: $settings.resumesPaused
                        )
                    }

                    SettingsGroup("Data") {
                        if let summary = session.saveSummary {
                            SettingsRow(
                                title: summary.identity.name,
                                detail: String(localized: "Day \(summary.day) • saved \(summary.savedAt.formatted(.relative(presentation: .named)))"),
                                systemImage: "externaldrive.fill"
                            )
                            SettingsDivider()
                            Button {
                                showsDeleteConfirmation = true
                            } label: {
                                SettingsRow(
                                    title: String(localized: "Delete saved campaign"),
                                    detail: String(localized: "Permanently removes the stored game."),
                                    systemImage: "trash.fill",
                                    tint: Theme.coral
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            SettingsRow(
                                title: String(localized: "No saved campaign"),
                                detail: String(localized: "Start a new game from the title screen."),
                                systemImage: "externaldrive"
                            )
                        }
                    }

                    #if DEBUG
                    SettingsGroup("Developer") {
                        SettingsToggle(
                            title: String(localized: "Performance HUD"),
                            detail: String(localized: "Map fps, node and draw counts, plus simulation tick, snapshot and save timings."),
                            systemImage: "speedometer",
                            isOn: $settings.showsPerformanceOverlay
                        )
                    }
                    #endif

                    SettingsGroup("About") {
                        SettingsRow(
                            title: String(localized: "Version"),
                            detail: settings.appVersion,
                            systemImage: "info.circle.fill"
                        )
                        SettingsDivider()
                        SettingsRow(
                            title: String(localized: "Save format"),
                            detail: String(localized: "v\(SaveRepository.currentSaveVersion)"),
                            systemImage: "doc.badge.gearshape.fill"
                        )
                    }

                    Color.clear.frame(height: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            if showsDeleteConfirmation {
                deleteConfirmation
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsDeleteConfirmation)
        .presentationBackground(Theme.backgroundTop)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.gg(30, .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var deleteConfirmation: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { showsDeleteConfirmation = false }

            VStack(spacing: 16) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.coral)

                VStack(spacing: 8) {
                    Text("Delete saved campaign?")
                        .font(.gg(20, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("This cannot be undone.")
                        .font(.gg(13, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }

                VStack(spacing: 10) {
                    Button {
                        showsDeleteConfirmation = false
                        session.deleteSave()
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.coral))

                    Button {
                        showsDeleteConfirmation = false
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }
}

// MARK: - Building blocks

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            VStack(spacing: 0) { content }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.strokeSoft)
            .frame(height: 1)
            .padding(.leading, 52)
    }
}

private struct SettingsRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.gg(15, .bold))
                    .foregroundStyle(tint == Theme.coral ? Theme.coral : Theme.textPrimary)
                Text(detail)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct SettingsToggle: View {
    let title: String
    let detail: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.gg(15, .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Theme.gold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
