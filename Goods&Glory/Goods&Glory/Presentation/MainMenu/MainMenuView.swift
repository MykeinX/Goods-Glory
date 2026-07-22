//
//  MainMenuView.swift
//  Goods&Glory
//
//  Title screen: night-logistics backdrop, glowing brand mark, and a resume
//  card that tells the player what Continue will actually load.
//
//  Destructive confirmation is an in-game card, not a system action sheet:
//  the sheet read like an App Store purchase prompt and presenting UIKit
//  chrome over the animating canvas stalled the main thread.
//

import SwiftUI

struct MainMenuView: View {
    @Environment(GameSession.self) private var session

    @MainActor private var settings: AppSettings { AppSettings.shared }

    @State private var showsOverwriteConfirmation = false
    @State private var showsSettings = false

    /// The canvas is frozen while a modal is up so the title screen never
    /// competes with a presentation animation for the main thread.
    private var backgroundAnimates: Bool {
        settings.animatedTitleBackground && !showsOverwriteConfirmation && !showsSettings
    }

    var body: some View {
        ZStack {
            AnimatedWorldBackground(isAnimating: backgroundAnimates)

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                brandBlock
                Spacer(minLength: 24)
                Spacer(minLength: 24)
                actions
            }

            if showsOverwriteConfirmation {
                overwriteConfirmation
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsOverwriteConfirmation)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        // The founding screen's name field is the first text input in the game;
        // paying for the keyboard here, while the menu sits idle, keeps that
        // first tap instant.
        .prewarmsKeyboard()
    }

    // MARK: - Brand

    private var brandBlock: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Theme.gold.opacity(0.18))
                    .frame(width: 150, height: 150)
                    .blur(radius: 30)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Theme.backgroundTop)
                    .frame(width: 96, height: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.gold, Theme.gold.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Theme.gold.opacity(0.5), radius: 18, y: 6)
            }

            VStack(spacing: 8) {
                Text("Goods & Glory")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Theme.gold.opacity(0.85)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("Build a global logistics empire.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            if let summary = session.saveSummary {
                ResumeCard(summary: summary) { session.continueGame() }

                Button {
                    showsOverwriteConfirmation = true
                } label: {
                    Label("New Game", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    session.beginFounding()
                } label: {
                    Label("New Game", systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            Button {
                showsSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .font(.gg(14, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Text(verbatim: "v\(settings.appVersion)")
                .font(.gg(10.5, .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 34)
    }

    // MARK: - In-game destructive confirmation

    private var overwriteConfirmation: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { showsOverwriteConfirmation = false }

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.coral)

                VStack(spacing: 8) {
                    Text("Start a new campaign?")
                        .font(.gg(20, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your current campaign stays saved until you finish founding the new company. Cancelling the setup keeps it intact.")
                        .font(.gg(13, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    Button {
                        showsOverwriteConfirmation = false
                        session.beginFounding()
                    } label: {
                        Text("Continue to Founding")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        showsOverwriteConfirmation = false
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .padding(.horizontal, 32)
        }
        .transition(.opacity)
    }
}

// MARK: - Resume card

/// Continue button that doubles as a save slot: the player sees whose empire
/// they are resuming and how far along it is before committing.
private struct ResumeCard: View {
    let summary: SaveSummary
    let onTap: () -> Void

    private var accent: Color { Color(hex: summary.identity.colorHex) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                CompanyMark(
                    emblemSymbol: summary.identity.emblemSymbol,
                    color: accent,
                    size: 46
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.identity.name)
                        .font(.gg(17, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Text("Day \(summary.day)")
                        Text(Format.money(summary.cash))
                        Text("\(summary.vehicleCount) veh.")
                    }
                    .font(.gg(12, .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                    Text(summary.savedAt.formatted(.relative(presentation: .named)))
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.ink(on: accent))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(accent))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(accent.opacity(0.55), lineWidth: 1.4)
            )
            .shadow(color: accent.opacity(0.18), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Continue \(summary.identity.name), day \(summary.day)"))
    }
}
